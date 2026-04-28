"""Routes sources."""

import contextlib
import time
from collections import defaultdict
from urllib.parse import urlparse
from uuid import UUID

import structlog
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.exc import DBAPIError, SQLAlchemyError
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db, safe_async_session
from app.dependencies import get_current_user_id
from app.models.failed_source_attempt import FailedSourceAttempt
from app.models.source import Source
from app.models.user import UserInterest
from app.schemas.source import (
    SearchAbandonedRequest,
    SmartSearchRecentItem,
    SmartSearchRequest,
    SmartSearchResponse,
    SmartSearchResultItem,
    SourceCatalogResponse,
    SourceCreate,
    SourceDetectRequest,
    SourceDetectResponse,
    SourceResponse,
    SourceSearchResponse,
    ThemeFollowed,
    ThemesFollowedResponse,
    ThemeSourceGroup,
    ThemeSourcesResponse,
    UpdateSourceSubscriptionRequest,
    UpdateSourceWeightRequest,
)
from app.services.feed_cache import FEED_CACHE
from app.services.search.smart_source_search import (
    SmartSourceSearchService,
    mark_search_abandoned,
)
from app.services.source_service import SourceService
from app.services.sources_cache import SOURCES_CACHE
from app.utils.db_retry import retry_db_op

logger = structlog.get_logger()

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
    db: AsyncSession = Depends(get_db),
) -> SourceCatalogResponse:
    """Récupérer toutes les sources (curées + custom).

    Resilient read : per-user 30 s cache + retry on transient DB errors
    (PYTHON-4 / PYTHON-26 — pool pressure). Returns 503 ``sources_unavailable``
    on persistent failure so the mobile FriendlyErrorView can render the
    "Petit souci de serveur" copy instead of a raw DioException.
    """
    user_uuid = UUID(user_id)

    cached = SOURCES_CACHE.get(user_uuid)
    if cached is not None:
        return cached

    async with SOURCES_CACHE.lock(user_uuid):
        cached = SOURCES_CACHE.get(user_uuid)
        if cached is not None:
            return cached

        service = SourceService(db)
        try:
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


@router.get("/by-theme/{slug}", response_model=ThemeSourcesResponse)
async def get_sources_by_theme(
    slug: str,
    limit: int = 8,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> ThemeSourcesResponse:
    """Sources par thème : Curées → Candidates → Communauté."""
    from app.models.source import UserSource

    # Sources déjà suivies par l'utilisateur (pour flag is_trusted dans la réponse)
    trusted_stmt = select(UserSource.source_id).where(UserSource.user_id == user_id)
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
                .join(UserSource, UserSource.source_id == Source.id)
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
    from app.models.source import UserSource

    # Get user interests
    stmt = select(UserInterest.interest_slug).where(UserInterest.user_id == user_id)
    result = await db.execute(stmt)
    slugs = [row[0] for row in result.fetchall()]

    themes = []
    for slug in slugs:
        stmt_count = (
            select(func.count())
            .select_from(Source)
            .join(UserSource, UserSource.source_id == Source.id)
            .where(UserSource.user_id == user_id)
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


@router.put("/{source_id}/weight", response_model=SourceResponse)
async def update_source_weight(
    source_id: UUID,
    data: UpdateSourceWeightRequest,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> SourceResponse:
    """Mettre à jour le poids d'une source (0.2, 1.0, 2.0)."""
    service = SourceService(db)
    result = await service.update_source_weight(
        user_id, str(source_id), data.priority_multiplier
    )

    if not result:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Source not found or not followed by user",
        )

    await db.commit()
    FEED_CACHE.invalidate(UUID(user_id))
    SOURCES_CACHE.invalidate(UUID(user_id))
    return result


@router.put("/{source_id}/subscription", response_model=SourceResponse)
async def update_source_subscription(
    source_id: UUID,
    data: UpdateSourceSubscriptionRequest,
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> SourceResponse:
    """Mettre à jour l'abonnement premium d'une source."""
    service = SourceService(db)
    result = await service.update_source_subscription(
        user_id, str(source_id), data.has_subscription
    )

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
