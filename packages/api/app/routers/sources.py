"""Routes sources."""

import contextlib
import time
from collections import defaultdict
from datetime import UTC, datetime, timedelta
from urllib.parse import urlparse
from uuid import UUID

import structlog
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query, status
from sqlalchemy import and_, func, select
from sqlalchemy.exc import DBAPIError, SQLAlchemyError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.database import get_db, safe_async_session
from app.dependencies import get_current_user_id
from app.models.content import Content
from app.models.enums import InterestState
from app.models.failed_source_attempt import FailedSourceAttempt
from app.models.source import Source, UserSource
from app.models.user import UserInterest
from app.schemas.content import ContentResponse
from app.schemas.source import (
    CoverageResponse,
    CoverageRow,
    PremiumConnectionResponse,
    RecentItemsRequest,
    RecentItemsResponse,
    SearchAbandonedRequest,
    SmartSearchRecentItem,
    SmartSearchRequest,
    SmartSearchResponse,
    SmartSearchResultItem,
    SourceCatalogResponse,
    SourceCreate,
    SourceDetectRequest,
    SourceDetectResponse,
    SourceProfileResponse,
    SourceRecentItems,
    SourceResponse,
    SourceSearchResponse,
    ThemeFollowed,
    ThemesFollowedResponse,
    ThemeShare,
    ThemeSourceGroup,
    ThemeSourcesResponse,
    UpdateSourceSubscriptionRequest,
)
from app.services.feed_cache import FEED_CACHE
from app.services.pepite_service import PepiteService
from app.services.premium_curated_sources import (
    PREMIUM_CURATED_MAP,
    is_paywalled_source,
)
from app.services.search.smart_source_search import (
    SmartSourceSearchService,
    mark_search_abandoned,
)
from app.services.source_service import PremiumConnectionNotEnabled, SourceService
from app.services.sources_cache import SOURCES_CACHE
from app.utils.db_retry import retry_db_op

logger = structlog.get_logger()
FOLLOWED_SOURCE_STATES = (InterestState.FOLLOWED, InterestState.FAVORITE)

router = APIRouter()


async def _log_failed_source_attempt(
    *,
    user_id: str,
    input_text: str,
    input_type: str,
    endpoint: str,
    error_message: str | None = None,
) -> None:
    # Uses its own session so the commit survives the HTTPException that the
    # caller is about to raise. The request-scoped `get_db` dependency does
    # rollback-on-BaseException (database.py:257) which would otherwise erase
    # the insert.
    try:
        async with safe_async_session() as session:
            session.add(
                FailedSourceAttempt(
                    user_id=UUID(user_id),
                    input_text=input_text[:500],
                    input_type=input_type,
                    endpoint=endpoint,
                    error_message=error_message[:1000] if error_message else None,
                )
            )
            await session.commit()
    except Exception as log_exc:
        logger.warning(
            "failed_source_attempt_log_error",
            endpoint=endpoint,
            error=str(log_exc),
            exc_type=type(log_exc).__name__,
        )


# ─── Endpoint-level rate limiter for smart-search ────────────────
# Prevents hammering: max 10 requests per minute per user.
_search_request_log: dict[str, list[float]] = defaultdict(list)
_SEARCH_RATE_LIMIT = 10  # requests
_SEARCH_RATE_WINDOW = 60  # seconds


def _check_search_endpoint_rate(user_id: str) -> bool:
    """Returns True if user is within endpoint rate limit."""
    now = time.monotonic()
    timestamps = _search_request_log[user_id]
    # Trim old entries
    cutoff = now - _SEARCH_RATE_WINDOW
    _search_request_log[user_id] = [t for t in timestamps if t > cutoff]
    if len(_search_request_log[user_id]) >= _SEARCH_RATE_LIMIT:
        return False
    _search_request_log[user_id].append(now)
    return True


@router.get("", response_model=SourceCatalogResponse)
async def get_sources(
    user_id: str = Depends(get_current_user_id),
) -> SourceCatalogResponse:
    """Récupérer toutes les sources (curées + custom).

    Resilient read : per-user 30 s cache + retry on transient DB errors
    (PYTHON-4 / PYTHON-26 — pool pressure). Returns 503 ``sources_unavailable``
    on persistent failure so the mobile FriendlyErrorView can render the
    "Petit souci de serveur" copy instead of a raw DioException.

    Fix PYTHON-4R / PYTHON-3C (IdleInTransactionSessionTimeout lors de
    l'onboarding) : la session DB est ouverte APRÈS l'acquisition du lock
    SOURCES_CACHE, pas avant. Auparavant, ``Depends(get_db)`` ouvrait
    ``BEGIN; SET LOCAL idle_in_transaction_session_timeout=10s`` avant même
    d'avoir le lock — si un request concurrent tenait le lock plus de 10 s
    (ex. retry mobile), Postgres tuait la transaction idle et le request
    retombait en 503 après 3 retries exhaustés.
    """
    user_uuid = UUID(user_id)

    cached = SOURCES_CACHE.get(user_uuid)
    if cached is not None:
        return cached

    async with SOURCES_CACHE.lock(user_uuid):
        cached = SOURCES_CACHE.get(user_uuid)
        if cached is not None:
            return cached

        # Session ouverte ICI — après le lock, juste avant les queries.
        # Le timer idle_in_transaction_session_timeout ne démarre qu'à ce
        # moment, éliminant le risque de timeout pendant l'attente de lock.
        try:
            async with safe_async_session() as db:
                service = SourceService(db)
                sources = await retry_db_op(
                    lambda: service.get_all_sources(user_id),
                    session=db,
                    op_name="sources.get_all",
                )
        except (SQLAlchemyError, DBAPIError) as e:
            logger.error(
                "sources_endpoint_db_error",
                user_id=user_id,
                exc_type=type(e).__name__,
                error=str(e)[:300],
            )
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="sources_unavailable",
            )

        SOURCES_CACHE.put(user_uuid, sources)
        return sources


@router.get("/catalog", response_model=list[SourceResponse])
async def get_catalog(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> list[SourceResponse]:
    """Récupérer le catalogue des sources curées."""
    service = SourceService(db)
    sources = await service.get_curated_sources(user_id)

    return sources


@router.get("/trending", response_model=list[SourceResponse])
async def get_trending_sources(
    limit: int = 10,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> list[SourceResponse]:
    """Récupérer les sources les plus populaires de la communauté."""
    service = SourceService(db)
    sources = await service.get_trending_sources(user_id=user_id, limit=limit)
    return sources


@router.get("/pepites", response_model=list[SourceResponse])
async def get_pepites(
    limit: int = 4,
    force_show: bool = False,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> list[SourceResponse]:
    """Carousel "Pépites" — sources curées à pousser dans le feed.

    Liste vide si l'utilisateur ne remplit pas les conditions
    (rate-limité ou dismiss récent).
    """
    service = PepiteService(db)
    sources = await service.get_pepites_for_user(
        user_id, limit=limit, force_show=force_show
    )
    if sources and not force_show:
        await db.commit()
    return sources


@router.post("/pepites/dismiss", status_code=status.HTTP_204_NO_CONTENT)
async def dismiss_pepites_carousel(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> None:
    """Dismiss le carousel "Pépites" — cool-down 7j avant réapparition."""
    service = PepiteService(db)
    await service.dismiss_pepite_carousel(user_id)
    await db.commit()
    return None


THEME_LABELS = {
    "tech": "Tech",
    "society": "Société",
    "environment": "Environnement",
    "economy": "Économie",
    "politics": "Politique",
    "culture": "Culture",
    "science": "Science",
    "international": "International",
}


def _source_to_response(
    s: Source, *, trusted_ids: set[UUID] | None = None
) -> SourceResponse:
    """Convert Source model to SourceResponse.

    `trusted_ids` lets callers flag sources already followed by the current
    user (used by the theme suggestions screen to show "déjà suivie").
    """
    return SourceResponse(
        id=s.id,
        name=s.name,
        url=s.url,
        type=s.type,
        theme=s.theme,
        description=s.description,
        logo_url=s.logo_url,
        is_curated=s.is_curated,
        is_custom=not s.is_curated,
        is_trusted=trusted_ids is not None and s.id in trusted_ids,
        content_count=0,
        bias_stance=getattr(s.bias_stance, "value", "unknown"),
        reliability_score=getattr(s.reliability_score, "value", "unknown"),
        bias_origin=getattr(s.bias_origin, "value", "unknown"),
        secondary_themes=s.secondary_themes,
        granular_topics=s.granular_topics,
        source_tier=s.source_tier or "mainstream",
        score_independence=s.score_independence,
        score_rigor=s.score_rigor,
        score_ux=s.score_ux,
        recommended_by=getattr(s, "recommended_by", None),
        recommendation_reason=getattr(s, "recommendation_reason", None),
        has_paywall=is_paywalled_source(s, curated_map=PREMIUM_CURATED_MAP),
        premium_connection=PremiumConnectionResponse.from_source(
            s, curated_map=PREMIUM_CURATED_MAP
        ),
    )


@router.post("/smart-search", response_model=SmartSearchResponse)
async def smart_search(
    data: SmartSearchRequest,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> SmartSearchResponse:
    """Recherche intelligente multi-sources."""
    if not _check_search_endpoint_rate(user_id):
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many requests (max 10/minute)",
        )

    async def _release_db() -> None:
        # Hand the request-scoped session back to the pool before the service
        # enters its slow external phase (LLM/Brave/GoogleNews). FastAPI's
        # `get_db` dependency wraps `close()` in a finally — calling it here
        # is safe because AsyncSession.close() is idempotent.
        try:
            await db.commit()
        except Exception:
            with contextlib.suppress(Exception):
                await db.rollback()
        await db.close()

    service = SmartSourceSearchService(db, on_phase1_done=_release_db)
    try:
        result = await service.search(
            data.query,
            user_id,
            content_type=data.content_type,
            expand=data.expand,
        )

        if result.get("error") == "rate_limit_exceeded":
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Rate limit exceeded (30 searches/day)",
            )

        return SmartSearchResponse(
            query_normalized=result["query_normalized"],
            results=[
                SmartSearchResultItem(
                    name=r["name"],
                    type=r["type"],
                    url=r["url"],
                    feed_url=r["feed_url"],
                    favicon_url=r.get("favicon_url"),
                    description=r.get("description"),
                    in_catalog=r.get("in_catalog", False),
                    is_curated=r.get("is_curated", False),
                    source_id=r.get("source_id"),
                    recent_items=[
                        SmartSearchRecentItem(**i) for i in r.get("recent_items", [])
                    ],
                    score=r.get("score", 0.0),
                    source_layer=r.get("source_layer", "unknown"),
                )
                for r in result.get("results", [])
            ],
            cache_hit=result.get("cache_hit", False),
            layers_called=result.get("layers_called", []),
            latency_ms=result.get("latency_ms", 0),
        )
    finally:
        await service.close()


@router.post("/search-abandoned", status_code=204)
async def log_search_abandoned(
    data: SearchAbandonedRequest,
    user_id: str = Depends(get_current_user_id),
) -> None:
    """Enregistre une recherche sans ajout de source (signal mobile).

    Marque le dernier `source_search_logs` correspondant comme abandonné, et
    conserve l'insert legacy dans `failed_source_attempts` pour rétrocompat.
    """
    await mark_search_abandoned(user_id, data.query)
    await _log_failed_source_attempt(
        user_id=user_id,
        input_text=data.query,
        input_type="keyword",
        endpoint="smart-search",
    )


@router.post("/recent-items", response_model=RecentItemsResponse)
async def get_recent_items(
    data: RecentItemsRequest,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> RecentItemsResponse:
    """Derniers contenus par source, groupés (animation de conclusion onboarding).

    Bornes anti-abus via le schéma : max 30 sources, max 5 items par source.
    """
    if not data.source_ids:
        return RecentItemsResponse(sources=[])

    rn = (
        func.row_number()
        .over(
            partition_by=Content.source_id,
            order_by=Content.published_at.desc(),
        )
        .label("rn")
    )
    ranked = (
        select(
            Content.source_id,
            Content.title,
            Content.published_at,
            Content.theme,
            rn,
        )
        .where(Content.source_id.in_(data.source_ids))
        .subquery()
    )
    rows = (
        await db.execute(
            select(
                ranked.c.source_id,
                ranked.c.title,
                ranked.c.published_at,
                ranked.c.theme,
            )
            .where(ranked.c.rn <= data.per_source)
            .order_by(ranked.c.source_id, ranked.c.published_at.desc())
        )
    ).all()

    items_by_source: dict[UUID, list[SmartSearchRecentItem]] = defaultdict(list)
    for row in rows:
        items_by_source[row.source_id].append(
            SmartSearchRecentItem(
                title=row.title,
                published_at=row.published_at.isoformat() if row.published_at else "",
                theme=row.theme,
            )
        )

    sources_result = await db.execute(
        select(Source.id, Source.name, Source.logo_url).where(
            Source.id.in_(items_by_source.keys())
        )
    )
    source_meta = {row.id: row for row in sources_result.all()}

    # Ordre de la requête préservé pour un rendu déterministe côté mobile.
    grouped = [
        SourceRecentItems(
            source_id=source_id,
            name=source_meta[source_id].name,
            logo_url=source_meta[source_id].logo_url,
            items=items_by_source[source_id],
        )
        for source_id in dict.fromkeys(data.source_ids)
        if source_id in source_meta
    ]
    return RecentItemsResponse(sources=grouped)


@router.get("/by-theme/{slug}", response_model=ThemeSourcesResponse)
async def get_sources_by_theme(
    slug: str,
    limit: int = 8,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> ThemeSourcesResponse:
    """Sources par thème : Curées → Candidates → Communauté."""
    # Sources déjà suivies par l'utilisateur (pour flag is_trusted dans la réponse)
    trusted_stmt = select(UserSource.source_id).where(
        UserSource.user_id == UUID(user_id),
        UserSource.state.in_(FOLLOWED_SOURCE_STATES),
    )
    trusted_result = await db.execute(trusted_stmt)
    trusted_ids: set[UUID] = {row[0] for row in trusted_result.all()}

    groups: list[ThemeSourceGroup] = []
    total = 0

    # Curées
    stmt_curated = (
        select(Source)
        .where(Source.is_active.is_(True))
        .where(Source.is_curated.is_(True))
        .where((Source.theme == slug) | (Source.secondary_themes.any(slug)))
        .order_by(Source.name)
        .limit(limit)
    )
    result = await db.execute(stmt_curated)
    curated_sources = result.scalars().all()
    curated_responses = [
        _source_to_response(s, trusted_ids=trusted_ids) for s in curated_sources
    ]
    if curated_responses:
        groups.append(ThemeSourceGroup(label="Curées", sources=curated_responses))
        total += len(curated_responses)

    # Candidates (non-curated)
    remaining = limit - total
    candidate_sources = []
    if remaining > 0:
        stmt_candidates = (
            select(Source)
            .where(Source.is_active.is_(True))
            .where(Source.is_curated.is_(False))
            .where((Source.theme == slug) | (Source.secondary_themes.any(slug)))
            .order_by(Source.name)
            .limit(remaining)
        )
        result = await db.execute(stmt_candidates)
        candidate_sources = result.scalars().all()
        candidate_responses = [
            _source_to_response(s, trusted_ids=trusted_ids) for s in candidate_sources
        ]
        if candidate_responses:
            groups.append(
                ThemeSourceGroup(label="Candidates", sources=candidate_responses)
            )
            total += len(candidate_responses)

    # Communauté fallback (if total < 3)
    if total < 3:
        community_remaining = max(3 - total, 0)
        if community_remaining > 0:
            exclude_ids = [s.id for s in curated_sources] + [
                s.id for s in candidate_sources
            ]

            stmt_community = (
                select(Source, func.count(UserSource.user_id).label("followers"))
                .join(
                    UserSource,
                    and_(
                        UserSource.source_id == Source.id,
                        UserSource.state.in_(FOLLOWED_SOURCE_STATES),
                    ),
                )
                .where(Source.is_active.is_(True))
            )
            if exclude_ids:
                stmt_community = stmt_community.where(Source.id.notin_(exclude_ids))
            stmt_community = (
                stmt_community.group_by(Source.id)
                .order_by(func.count(UserSource.user_id).desc())
                .limit(community_remaining)
            )
            result = await db.execute(stmt_community)
            community_rows = result.all()
            community_responses = [
                _source_to_response(row[0], trusted_ids=trusted_ids)
                for row in community_rows
            ]
            if community_responses:
                groups.append(
                    ThemeSourceGroup(label="Communauté", sources=community_responses)
                )
                total += len(community_responses)

    return ThemeSourcesResponse(theme=slug, groups=groups, total_count=total)


@router.get("/themes-followed", response_model=ThemesFollowedResponse)
async def get_themes_followed(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> ThemesFollowedResponse:
    """Thèmes suivis par l'utilisateur avec count de sources."""
    # Get user interests
    user_uuid = UUID(user_id)
    stmt = select(UserInterest.interest_slug).where(UserInterest.user_id == user_uuid)
    result = await db.execute(stmt)
    slugs = [row[0] for row in result.fetchall()]

    themes = []
    for slug in slugs:
        stmt_count = (
            select(func.count())
            .select_from(Source)
            .join(UserSource, UserSource.source_id == Source.id)
            .where(UserSource.user_id == user_uuid)
            .where(UserSource.state.in_(FOLLOWED_SOURCE_STATES))
            .where(Source.is_active.is_(True))
            .where((Source.theme == slug) | (Source.secondary_themes.any(slug)))
        )
        result = await db.execute(stmt_count)
        count = result.scalar() or 0

        themes.append(
            ThemeFollowed(
                slug=slug,
                label=THEME_LABELS.get(slug, slug.capitalize()),
                followed_sources_count=count,
            )
        )

    return ThemesFollowedResponse(themes=themes)


@router.post("/custom", response_model=SourceResponse)
async def add_source(
    data: SourceCreate,
    background_tasks: BackgroundTasks,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> SourceResponse:
    """Ajouter une source personnalisée."""
    service = SourceService(db)

    try:
        source = await service.add_custom_source(user_id, str(data.url), data.name)
        await db.commit()
        FEED_CACHE.invalidate(UUID(user_id))
        SOURCES_CACHE.invalidate(UUID(user_id))

        # Trigger immediate sync in background after request returns (and DB commits)
        from app.workers.rss_sync import sync_source

        background_tasks.add_task(sync_source, str(source.id))

        return source
    except ValueError as e:
        await _log_failed_source_attempt(
            user_id=user_id,
            input_text=str(data.url),
            input_type="url",
            endpoint="custom",
            error_message=str(e),
        )
        logger.info(
            "failed_source_attempt", endpoint="custom", input=str(data.url)[:100]
        )
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e),
        )


@router.delete("/{source_id}")
async def delete_source(
    source_id: UUID,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> dict[str, str]:
    """Supprimer une source personnalisée."""
    service = SourceService(db)
    deleted = await service.delete_custom_source(user_id, str(source_id))

    if not deleted:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Source not found or not owned by user",
        )

    await db.commit()
    FEED_CACHE.invalidate(UUID(user_id))
    SOURCES_CACHE.invalidate(UUID(user_id))
    return {"status": "deleted"}


@router.post("/detect", response_model=SourceDetectResponse | SourceSearchResponse)
async def detect_source(
    data: SourceDetectRequest,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> SourceDetectResponse | SourceSearchResponse:
    """Détecter le type d'une URL source ou chercher par mot-clé."""
    service = SourceService(db)

    try:
        url_input = data.url.strip()

        # URL detection via urlparse — handles protocols and bare domains
        if url_input.startswith(("http://", "https://")):
            is_url_like = True
        else:
            # Try parsing as https:// to check if it has a valid netloc
            parsed = urlparse(f"https://{url_input}")
            is_url_like = bool(
                parsed.netloc
                and "." in parsed.netloc
                and not parsed.netloc.startswith(".")
            )

        if is_url_like and not url_input.startswith("http"):
            url_input = "https://" + url_input

        if is_url_like:
            result = await service.detect_source(url_input)
            return result
        else:
            # It's a keyword search
            results = await service.search_sources(url_input, user_id=user_id)
            return SourceSearchResponse(results=results)
    except ValueError as e:
        await _log_failed_source_attempt(
            user_id=user_id,
            input_text=data.url.strip(),
            input_type="url" if is_url_like else "keyword",
            endpoint="detect",
            error_message=str(e),
        )
        logger.info(
            "failed_source_attempt", endpoint="detect", input=data.url.strip()[:100]
        )
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e),
        )


# Nombre maximum de thèmes affichés individuellement ; la longue traîne au-delà
# est regroupée dans une ligne unique `theme="autres"`.
COVERAGE_TOP_N = 6
# Clé brute utilisée pour la ligne agrégée (longue traîne + thèmes NULL).
COVERAGE_OTHER_THEME = "autres"
# Espace fine insécable (U+202F) — séparateur des milliers en typographie FR.
_NARROW_NBSP = " "


def _format_fr_thousands(value: int) -> str:
    """Formate un entier avec une espace fine insécable comme séparateur des milliers."""
    return f"{value:,}".replace(",", _NARROW_NBSP)


async def _aggregate_source_themes(
    db: AsyncSession,
    source_id: UUID,
    *,
    days: int,
) -> tuple[list[tuple[str, int]], int]:
    """Agrège les contenus d'une source par thème sur une fenêtre glissante.

    Helper partagé par `/coverage` et `/profile` (zéro duplication).

    Renvoie `(rows, total)` :
    - `total` = nombre d'articles publiés sur la fenêtre, tous thèmes confondus
      (avant troncature top-N) ;
    - `rows` = liste `(theme, count)` triée par volume décroissant : les
      `COVERAGE_TOP_N` thèmes nommés les plus volumineux, suivis d'une ligne
      `COVERAGE_OTHER_THEME` repliant la longue traîne **et** les thèmes NULL
      (présente seulement si non vide). Liste vide quand `total == 0`.
    """
    cutoff = datetime.now(UTC) - timedelta(days=days)

    result = await db.execute(
        select(Content.theme, func.count())
        .where(Content.source_id == source_id)
        .where(Content.published_at >= cutoff)
        .group_by(Content.theme)
    )
    aggregates = result.all()

    # total = somme sur TOUS les thèmes de la fenêtre (avant troncature top-N).
    total = sum(int(count) for _theme, count in aggregates)
    if total == 0:
        return [], 0

    # Sépare les thèmes nommés (non-NULL) de la part NULL, qui ira dans « autres ».
    named: list[tuple[str, int]] = []
    other_count = 0
    for theme, count in aggregates:
        count = int(count)
        if theme is None:
            other_count += count
        else:
            named.append((theme, count))

    named.sort(key=lambda item: item[1], reverse=True)

    # Top N affichés individuellement ; le reste rejoint « autres ».
    head = named[:COVERAGE_TOP_N]
    tail = named[COVERAGE_TOP_N:]
    other_count += sum(count for _theme, count in tail)

    rows: list[tuple[str, int]] = list(head)
    if other_count > 0:
        rows.append((COVERAGE_OTHER_THEME, other_count))
    return rows, total


@router.get("/{source_id}/coverage", response_model=CoverageResponse)
async def get_source_coverage(
    source_id: UUID,
    days: int = Query(default=30, ge=1, le=365),
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> CoverageResponse:
    """Couverture par thèmes d'une source sur une fenêtre glissante.

    Agrège `contents` par `theme` sur les `days` derniers jours. Trie par
    volume décroissant, conserve le top N et regroupe la longue traîne (ainsi
    que les thèmes NULL) dans une ligne unique `autres`. La clé `theme` reste
    brute : le mapping label/couleur est fait côté front.
    """
    period_label = f"{days} derniers jours"
    rows, total_count = await _aggregate_source_themes(db, source_id, days=days)

    if total_count == 0:
        return CoverageResponse(
            period_label=period_label,
            total_count=0,
            caption="Aucun article publié sur la période",
            rows=[],
        )

    coverage_rows = [
        CoverageRow(theme=theme, count=count, pct=round(count / total_count * 100))
        for theme, count in rows
    ]

    noun = "article publié" if total_count == 1 else "articles publiés"
    caption = f"{_format_fr_thousands(total_count)} {noun} sur la période"

    return CoverageResponse(
        period_label=period_label,
        total_count=total_count,
        caption=caption,
        rows=coverage_rows,
    )


@router.get("/{source_id}/profile", response_model=SourceProfileResponse)
async def get_source_profile(
    source_id: UUID,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> SourceProfileResponse:
    """Profil unifié d'une source pour la fiche v3 (lecture seule).

    Une seule réponse regroupe : l'identité de la source, sa couverture par
    thèmes sur 30 jours (`theme_distribution` + `articles_30d`), la date du
    plus ancien contenu connu (`oldest_content_at`, hors fenêtre, pour clamper
    la fréquence côté mobile) et ses 3 articles les plus récents (objets
    `Content` complets → carte standard cliquable). Placé après `/coverage`,
    donc après toutes les routes statiques (`/catalog`, `/trending`…).
    """
    source = (
        await db.execute(select(Source).where(Source.id == source_id))
    ).scalar_one_or_none()
    if source is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Source not found"
        )

    # Source suivie par l'utilisateur courant ? → flag is_trusted (réponse
    # source) + is_followed_source (cartes article).
    followed = (
        await db.execute(
            select(UserSource.source_id).where(
                UserSource.user_id == UUID(user_id),
                UserSource.source_id == source_id,
                UserSource.state.in_(FOLLOWED_SOURCE_STATES),
            )
        )
    ).first() is not None

    source_response = _source_to_response(
        source, trusted_ids={source_id} if followed else set()
    )

    rows, total = await _aggregate_source_themes(db, source_id, days=30)
    theme_distribution = [
        ThemeShare(theme=theme, count=count, share=count / total if total else 0.0)
        for theme, count in rows
    ]

    # Plus ancien contenu sur TOUT l'historique (hors fenêtre 30 j).
    oldest_content_at = (
        await db.execute(
            select(func.min(Content.published_at)).where(Content.source_id == source_id)
        )
    ).scalar_one_or_none()

    recent_result = await db.execute(
        select(Content)
        .options(selectinload(Content.source))
        .where(Content.source_id == source_id)
        .order_by(Content.published_at.desc())
        .limit(3)
    )
    recent_articles: list[ContentResponse] = []
    for content in recent_result.scalars().all():
        item = ContentResponse.model_validate(content)
        # `status`, `is_saved`… retombent sur leurs défauts (absents de l'ORM
        # Content) ; on renseigne le seul flag dérivable ici.
        item.is_followed_source = followed
        recent_articles.append(item)

    return SourceProfileResponse(
        source=source_response,
        recent_articles=recent_articles,
        theme_distribution=theme_distribution,
        articles_30d=total,
        oldest_content_at=oldest_content_at,
    )


@router.put("/{source_id}/subscription", response_model=SourceResponse)
async def update_source_subscription(
    source_id: UUID,
    data: UpdateSourceSubscriptionRequest,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> SourceResponse:
    """Mettre à jour l'abonnement premium d'une source."""
    service = SourceService(db)
    try:
        result = await service.update_source_subscription(
            user_id, str(source_id), data.has_subscription
        )
    except PremiumConnectionNotEnabled:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Premium connection is not enabled for this source",
        ) from None

    if not result:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Source not found or not followed by user",
        )

    await db.commit()
    FEED_CACHE.invalidate(UUID(user_id))
    SOURCES_CACHE.invalidate(UUID(user_id))
    return result


@router.post("/{source_id}/trust")
async def trust_source(
    source_id: UUID,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> dict[str, str]:
    """Ajouter une source aux sources de confiance."""
    service = SourceService(db)
    success = await service.trust_source(user_id, str(source_id))

    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Source not found",
        )

    await db.commit()
    FEED_CACHE.invalidate(UUID(user_id))
    SOURCES_CACHE.invalidate(UUID(user_id))
    return {"status": "trusted"}


@router.delete("/{source_id}/trust")
async def untrust_source(
    source_id: UUID,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> dict[str, str]:
    """Retirer une source des sources de confiance."""
    service = SourceService(db)
    success = await service.untrust_source(user_id, str(source_id))

    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Source not found or not trusted",
        )

    await db.commit()
    FEED_CACHE.invalidate(UUID(user_id))
    SOURCES_CACHE.invalidate(UUID(user_id))
    return {"status": "untrusted"}
