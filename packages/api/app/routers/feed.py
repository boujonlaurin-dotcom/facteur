import json
import re
from datetime import UTC, datetime, timedelta
from uuid import UUID

import structlog
from fastapi import APIRouter, Depends, Query, Response
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user_id
from app.models.content import UserContentStatus
from app.models.enums import ContentType, FeedFilterMode
from app.schemas.content import (
    FeedRefreshRequest,
    FeedRefreshResponse,
    FeedRefreshUndoRequest,
    PreviousImpression,
)
from app.schemas.feed import (
    CarouselInfo,
    CarouselItemBadge,
    ClusterInfo,
    EntityOverflowInfo,
    FeedResponse,
    KeywordOverflowInfo,
    KeywordOverflowSourceInfo,
    OverflowSourceInfo,
    PaginationMeta,
    SourceOverflowInfo,
    TopicOverflowInfo,
    TrendingTopicResponse,
)
from app.services.feed_cache import FEED_CACHE
from app.services.recommendation.french_stopwords import FRENCH_STOP_WORDS
from app.services.recommendation_service import RecommendationService

logger = structlog.get_logger()


async def _resolve_topic_param(
    topic: str | None, user_uuid: UUID, db: AsyncSession
) -> str | None:
    """Story 22.1 — `topic` accepte un slug ou un UUID stringified custom_topic.

    Si `topic` parse en UUID, lookup `user_topic_profiles` scoped user_id
    (sécurité : pas de cross-user leak). Si trouvé → utilise `slug_parent`
    pour le filtre (matche `Content.topics` via `apply_topic_filter`). Si
    UUID inconnu pour ce user → retourne le slug originel (le filtre vide
    retournera 0 résultats côté pipeline). Si `topic` n'est pas un UUID
    valide → comportement actuel (slug ML granulaire).
    """
    if topic is None:
        return None
    try:
        topic_uuid = UUID(topic)
    except ValueError:
        return topic

    from sqlalchemy import select as sa_select

    from app.models.user_topic_profile import UserTopicProfile

    slug_parent = (
        await db.execute(
            sa_select(UserTopicProfile.slug_parent).where(
                UserTopicProfile.id == topic_uuid,
                UserTopicProfile.user_id == user_uuid,
            )
        )
    ).scalar_one_or_none()
    return slug_parent if slug_parent else topic


def _best_keyword(titles: list[str]) -> str:
    """Extrait le mot-clé le plus fréquent d'une liste de titres d'articles."""
    freq: dict[str, int] = {}
    for title in titles:
        tokens = re.findall(r"[a-zàâäéèêëïîôùûüÿçœæ\-]+", title.lower())
        for token in tokens:
            if len(token) >= 4 and token not in FRENCH_STOP_WORDS:
                freq[token] = freq.get(token, 0) + 1
    if not freq:
        return titles[0][:30] if titles else ""
    return max(freq, key=lambda k: freq[k])


router = APIRouter()


def _is_default_view(
    *,
    limit: int,
    offset: int,
    content_type: ContentType | None,
    mode: FeedFilterMode | None,
    serein: bool,
    theme: str | None,
    topic: str | None,
    saved_only: bool,
    has_note: bool,
    source_id: str | None,
    entity: str | None,
    keyword: str | None,
    personalized: bool,
) -> bool:
    """Eligibility predicate for the page-1 cache.

    Only the cold-open / tab-switch landing view is cached: page 1, default
    page size, no filter, serein off. Filtered/paginated views bypass —
    lower volume, harder to invalidate, lower ROI. Cf. R5 in
    `docs/bugs/bug-infinite-load-requests.md`.
    """
    return (
        offset == 0
        and limit == 20
        and content_type is None
        and mode is None
        and not serein
        and theme is None
        and topic is None
        and not saved_only
        and not has_note
        and source_id is None
        and entity is None
        and keyword is None
        and not personalized
    )


@router.get("/", response_model=FeedResponse)
async def get_personalized_feed(
    limit: int = Query(20, ge=1, le=50),
    offset: int = Query(0, ge=0),
    content_type: ContentType | None = Query(None, alias="type"),
    mode: FeedFilterMode | None = Query(None),
    serein: bool = Query(False, description="Apply serein filter (overrides mode)"),
    theme: str | None = Query(
        None, description="Theme slug to filter by (e.g. 'tech', 'science')"
    ),
    topic: str | None = Query(
        None,
        description="Topic slug to filter by (e.g. 'startups', 'entrepreneurship')",
    ),
    saved_only: bool = Query(False, alias="saved"),
    has_note: bool = Query(False, alias="has_note"),
    source_id: str | None = Query(None, description="Source UUID to filter by"),
    entity: str | None = Query(None, description="Entity canonical name to filter by"),
    keyword: str | None = Query(
        None, description="Keyword to filter articles by title (ILIKE match)"
    ),
    include_unfollowed: bool = Query(
        False,
        description=(
            "When True AND keyword is set, expand the search to articles from "
            "sources the user does not follow (used by trending chip taps)."
        ),
    ),
    personalized: bool = Query(
        False,
        description=(
            "Restrict theme/topic candidates to followed sources, narrow to a "
            "24h window, and boost articles matching user_subtopics. Used by "
            "the Tournée du jour theme sections."
        ),
    ),
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """
    Récupère le feed personnalisé.

    Note: Le briefing (Top 3) a été déplacé vers l'endpoint dédié /api/digest.
    Le feed retourne uniquement les articles réguliers.

    Round 5 — Cache applicatif TTL 30s sur la vue par défaut (page=1, no
    filter, serein off). Hit retourne le payload sérialisé sans recompute.
    Single-flight via `FEED_CACHE.lock(user_id)` pour éviter le thundering
    herd au cache miss.
    """
    user_uuid = UUID(current_user_id)

    cache_eligible = FEED_CACHE.enabled and _is_default_view(
        limit=limit,
        offset=offset,
        content_type=content_type,
        mode=mode,
        serein=serein,
        theme=theme,
        topic=topic,
        saved_only=saved_only,
        has_note=has_note,
        source_id=source_id,
        entity=entity,
        keyword=keyword,
        personalized=personalized,
    )

    if cache_eligible:
        # Fast path: cached and fresh → no DB work, no Pydantic.
        cached = FEED_CACHE.get(user_uuid)
        if cached is not None:
            return Response(content=cached, media_type="application/json")

        # Single-flight: serialize concurrent first-misses for the same user.
        # 2nd+ waiters re-check after acquiring the lock and pick up the
        # payload populated by the 1st.
        async with FEED_CACHE.lock(user_uuid):
            cached = FEED_CACHE.get(user_uuid)
            if cached is not None:
                return Response(content=cached, media_type="application/json")
            response = await _compute_feed(
                db=db,
                user_uuid=user_uuid,
                limit=limit,
                offset=offset,
                content_type=content_type,
                mode=mode,
                serein=serein,
                theme=theme,
                topic=topic,
                saved_only=saved_only,
                has_note=has_note,
                source_id=source_id,
                entity=entity,
                keyword=keyword,
                include_unfollowed=include_unfollowed,
                personalized=personalized,
            )
            payload = json.dumps(response.model_dump(mode="json")).encode("utf-8")
            FEED_CACHE.put(user_uuid, payload)
            return Response(content=payload, media_type="application/json")

    response = await _compute_feed(
        db=db,
        user_uuid=user_uuid,
        limit=limit,
        offset=offset,
        content_type=content_type,
        mode=mode,
        serein=serein,
        theme=theme,
        topic=topic,
        saved_only=saved_only,
        has_note=has_note,
        source_id=source_id,
        entity=entity,
        keyword=keyword,
        include_unfollowed=include_unfollowed,
        personalized=personalized,
    )
    return response


async def _compute_feed(
    *,
    db: AsyncSession,
    user_uuid: UUID,
    limit: int,
    offset: int,
    content_type: ContentType | None,
    mode: FeedFilterMode | None,
    serein: bool,
    theme: str | None,
    topic: str | None,
    saved_only: bool,
    has_note: bool,
    source_id: str | None,
    entity: str | None,
    keyword: str | None,
    include_unfollowed: bool = False,
    personalized: bool = False,
) -> FeedResponse:
    """Run the full recommendation pipeline. Identical to the pre-Round-5
    body of `get_personalized_feed`, extracted for cache-miss reuse."""
    service = RecommendationService(db)

    # serein=True overrides mode to use the serein filter (same as INSPIRATION)
    if serein and not mode:
        mode = FeedFilterMode.INSPIRATION

    # Story 22.1 — `topic` accepte slug OU UUID stringified d'un custom_topic.
    topic = await _resolve_topic_param(topic, user_uuid, db)

    # Get Feed Items only - briefing moved to dedicated digest endpoint
    feed_items = await service.get_feed(
        user_id=user_uuid,
        limit=limit,
        offset=offset,
        content_type=content_type,
        mode=mode,
        saved_only=saved_only,
        theme=theme,
        topic=topic,
        has_note=has_note,
        source_id=source_id,
        entity=entity,
        keyword=keyword,
        serein=serein,
        include_unfollowed=include_unfollowed,
        personalized=personalized,
    )

    # Epic 11: Build clusters from custom topics (reuse from service, no duplicate query)
    user_custom_topics = service.user_custom_topics

    clusters_data: list[ClusterInfo] = []
    if user_custom_topics and not saved_only and not source_id:
        feed_items, raw_clusters = RecommendationService.build_clusters(
            feed_items, user_custom_topics
        )
        clusters_data = [ClusterInfo(**c) for c in raw_clusters]

    # Epic 12: Source overflow from chronological diversification
    overflow_data = [
        SourceOverflowInfo(source_id=sid, hidden_count=count)
        for sid, count in service.source_overflow.items()
    ]

    # Topic overflow from topic-aware regroupement (Phase 2)
    topic_overflow_data = [TopicOverflowInfo(**info) for info in service.topic_overflow]

    # Calculate pagination metadata based on the total candidate pool,
    # not the post-filtered response size (regroupement/clustering can shrink it)
    has_next = (offset + limit) < service.total_candidates

    # Keyword overflow from keyword regroupement
    keyword_overflow_data = []
    for info in service.keyword_overflow:
        sources = [KeywordOverflowSourceInfo(**s) for s in info.get("sources", [])]
        keyword_overflow_data.append(
            KeywordOverflowInfo(
                keyword=info["keyword"],
                filter_keyword=info.get("filter_keyword", info["keyword"]),
                display_label=info["display_label"],
                hidden_count=info["hidden_count"],
                hidden_ids=info["hidden_ids"],
                sources=sources,
                is_custom_topic=info.get("is_custom_topic", False),
            )
        )

    # Entity overflow from entity regroupement
    entity_overflow_data = []
    for info in service.entity_overflow:
        sources = [OverflowSourceInfo(**s) for s in info.get("sources", [])]
        entity_overflow_data.append(
            EntityOverflowInfo(
                entity_name=info["entity_name"],
                display_label=info["display_label"],
                hidden_count=info["hidden_count"],
                hidden_ids=info["hidden_ids"],
                sources=sources,
            )
        )
    # Carousels from overflow group promotion
    carousels_data = []
    for c in service.carousels:
        carousels_data.append(
            CarouselInfo(
                carousel_type=c["carousel_type"],
                title=c["title"],
                emoji=c["emoji"],
                position=c["position"],
                items=c["items"],
                badges=[CarouselItemBadge(**b) for b in c["badges"]],
            )
        )

    # Epic 13: Learning Checkpoint — include proposals on first page only.
    return FeedResponse(
        items=feed_items,
        pagination=PaginationMeta(
            page=(offset // limit) + 1,
            per_page=limit,
            total=0,  # Total unknown without additional query
            has_next=has_next,
        ),
        clusters=clusters_data,
        source_overflow=overflow_data,
        topic_overflow=topic_overflow_data,
        keyword_overflow=keyword_overflow_data,
        entity_overflow=entity_overflow_data,
        carousels=carousels_data,
    )


@router.post("/refresh", response_model=FeedRefreshResponse, status_code=200)
async def refresh_feed(
    body: FeedRefreshRequest,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """
    Marque les articles affichés comme 'déjà vus' pour le scoring.

    Upsert user_content_status avec last_impressed_at = now().
    Le status reste UNSEEN (pas d'exclusion du feed), seul le scoring
    applique un malus temporel via ImpressionLayer.

    Retourne `previous_impressions` — backup des `last_impressed_at` précédents
    pour chaque content_id (peut être None si pas de row préexistante),
    afin de permettre l'undo via POST /feed/refresh/undo.
    """
    from sqlalchemy import select
    from sqlalchemy.dialects.postgresql import insert

    from app.models.enums import ContentStatus

    user_uuid = UUID(current_user_id)
    now = datetime.now(UTC)

    # 1. Snapshot des valeurs précédentes (pour undo)
    existing_result = await db.execute(
        select(
            UserContentStatus.content_id,
            UserContentStatus.last_impressed_at,
        )
        .where(UserContentStatus.user_id == user_uuid)
        .where(UserContentStatus.content_id.in_(body.content_ids))
    )
    existing_map: dict[UUID, datetime | None] = {
        row.content_id: row.last_impressed_at for row in existing_result
    }
    previous_impressions = [
        PreviousImpression(
            content_id=cid,
            previous_last_impressed_at=existing_map.get(cid),
        )
        for cid in body.content_ids
    ]

    # 2. UPSERT last_impressed_at = now()
    refreshed = 0
    for content_id in body.content_ids:
        stmt = (
            insert(UserContentStatus)
            .values(
                user_id=user_uuid,
                content_id=content_id,
                status=ContentStatus.UNSEEN.value,
                last_impressed_at=now,
                created_at=now,
                updated_at=now,
            )
            .on_conflict_do_update(
                index_elements=["user_id", "content_id"],
                set_={"last_impressed_at": now, "updated_at": now},
            )
        )
        await db.execute(stmt)
        refreshed += 1

    await db.commit()
    FEED_CACHE.invalidate(user_uuid)
    logger.info("feed_refresh", user_id=current_user_id, refreshed=refreshed)
    return FeedRefreshResponse(
        refreshed=refreshed,
        previous_impressions=previous_impressions,
    )


@router.post("/refresh/undo", status_code=200)
async def undo_refresh(
    body: FeedRefreshUndoRequest,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """
    Annule un refresh précédent : restaure les `last_impressed_at` précédents.

    Pour chaque entrée :
    - Si `previous_last_impressed_at` est NULL, l'article revient à son état
      initial (jamais impressionné).
    - Sinon, le timestamp précédent est restauré → l'ImpressionLayer recalcule
      la pénalité sur la base de l'ancienne valeur.

    Idempotent : rejouer l'undo ne change rien (les valeurs sont déjà restaurées).
    """
    from sqlalchemy.dialects.postgresql import insert

    from app.models.enums import ContentStatus

    user_uuid = UUID(current_user_id)
    now = datetime.now(UTC)
    restored = 0

    for entry in body.previous_impressions:
        stmt = (
            insert(UserContentStatus)
            .values(
                user_id=user_uuid,
                content_id=entry.content_id,
                status=ContentStatus.UNSEEN.value,
                last_impressed_at=entry.previous_last_impressed_at,
                created_at=now,
                updated_at=now,
            )
            .on_conflict_do_update(
                index_elements=["user_id", "content_id"],
                set_={
                    "last_impressed_at": entry.previous_last_impressed_at,
                    "updated_at": now,
                },
            )
        )
        await db.execute(stmt)
        restored += 1

    await db.commit()
    FEED_CACHE.invalidate(user_uuid)
    logger.info("feed_refresh_undo", user_id=current_user_id, restored=restored)
    return {"restored": restored}


@router.post("/briefing/{content_id}/read", status_code=200)
async def mark_briefing_item_read(
    content_id: str,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Marque un item du briefing comme lu/consommé."""
    from sqlalchemy import update

    from app.models.daily_top3 import DailyTop3

    user_uuid = UUID(current_user_id)
    c_uuid = UUID(content_id)

    # FIX: Broaden window to last 48h to avoid timezone edge cases
    # (e.g. Generated at 23:00 UTC previous day)
    lookback_window = datetime.now(UTC) - timedelta(hours=48)

    # 1. Mark in DailyTop3
    stmt = (
        update(DailyTop3)
        .where(
            DailyTop3.user_id == user_uuid,
            DailyTop3.content_id == c_uuid,
            DailyTop3.generated_at >= lookback_window,
        )
        .values(consumed=True)
    )
    result = await db.execute(stmt)
    await db.commit()

    if result.rowcount == 0:
        logger.warning(
            "briefing_mark_read_not_found",
            user_id=str(user_uuid),
            content_id=str(c_uuid),
        )
    else:
        logger.info(
            "briefing_mark_read_success",
            user_id=str(user_uuid),
            updated_count=result.rowcount,
        )

    return {"message": "Briefing item marked as read", "updated": result.rowcount}


@router.get("/tab-counts")
async def get_tab_counts(
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Comptages d'articles récents non-lus pour chaque onglet favori.

    Requête légère (projection minimale, pas de scoring) appelée au
    chargement du feed pour afficher les badges sur les onglets.
    """
    import json as _json

    from sqlalchemy import exists, or_, select

    from app.models.content import Content
    from app.models.source import UserSource
    from app.models.user_topic_profile import UserTopicProfile
    from app.schemas.feed import TabCountsResponse
    from app.services.ml.topic_theme_mapper import TOPIC_TO_THEME

    user_uuid = UUID(current_user_id)
    cutoff = datetime.now(UTC) - timedelta(hours=48)

    followed_stmt = select(UserSource.source_id).where(UserSource.user_id == user_uuid)
    favorites_stmt = select(UserTopicProfile).where(
        UserTopicProfile.user_id == user_uuid,
        UserTopicProfile.priority_multiplier == 2.0,
    )

    followed_result = await db.execute(followed_stmt)
    followed_source_ids = {row[0] for row in followed_result.all()}
    favorite_profiles = list((await db.scalars(favorites_stmt)).all())

    if not followed_source_ids:
        return TabCountsResponse(total=0)

    # 2. Extract favorite slugs/names to count
    fav_topic_slugs: set[str] = set()
    fav_entity_names: set[str] = set()
    for prof in favorite_profiles:
        if prof.entity_type is not None:
            if prof.canonical_name:
                fav_entity_names.add(prof.canonical_name.lower())
        else:
            if prof.slug_parent:
                fav_topic_slugs.add(prof.slug_parent)

    # 3. Lightweight query: only columns needed for counting
    exclude_stmt = exists().where(
        UserContentStatus.content_id == Content.id,
        UserContentStatus.user_id == user_uuid,
        or_(
            UserContentStatus.is_hidden,
            UserContentStatus.status.in_(["seen", "consumed"]),
        ),
    )

    stmt = select(Content.id, Content.topics, Content.entities).where(
        Content.source_id.in_(list(followed_source_ids)),
        Content.published_at >= cutoff,
        ~exclude_stmt,
    )
    rows = (await db.execute(stmt)).all()

    # 4. Count in Python (single pass over lightweight rows)
    total = len(rows)
    topic_counts: dict[str, int] = {}
    entity_counts: dict[str, int] = {}
    theme_counts: dict[str, int] = {}

    for row in rows:
        topics = row.topics or []
        entities_raw = row.entities or []

        for slug in fav_topic_slugs:
            if slug in topics:
                topic_counts[slug] = topic_counts.get(slug, 0) + 1

        if fav_entity_names and entities_raw:
            for raw_entity in entities_raw:
                try:
                    parsed = _json.loads(raw_entity)
                    name = parsed.get("name", "").lower()
                except (ValueError, AttributeError):
                    name = raw_entity.lower()
                if name in fav_entity_names:
                    entity_counts[name] = entity_counts.get(name, 0) + 1

        # Theme: count each article once per theme (not per topic)
        seen_themes: set[str] = set()
        for topic_slug in topics:
            theme_slug = TOPIC_TO_THEME.get(topic_slug)
            if theme_slug and theme_slug not in seen_themes:
                seen_themes.add(theme_slug)
                theme_counts[theme_slug] = theme_counts.get(theme_slug, 0) + 1

    logger.info(
        "tab_counts_served",
        user_id=current_user_id,
        total=total,
        topic_count=len(topic_counts),
        entity_count=len(entity_counts),
        theme_count=len(theme_counts),
    )

    return TabCountsResponse(
        total=total,
        topics=topic_counts,
        entities=entity_counts,
        themes=theme_counts,
    )


@router.get("/trending-topics", response_model=list[TrendingTopicResponse])
async def get_trending_topics(
    limit: int = Query(8, ge=1, le=20),
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Retourne les sujets tendance du moment (clusters multi-sources des dernières 24h)."""
    from sqlalchemy import select
    from sqlalchemy.orm import selectinload

    from app.models.content import Content
    from app.services.briefing.importance_detector import ImportanceDetector

    cutoff = datetime.now(UTC) - timedelta(hours=24)
    stmt = (
        select(Content)
        .options(selectinload(Content.source))
        .where(Content.published_at >= cutoff)
        .order_by(Content.published_at.desc())
    )
    result = await db.execute(stmt)
    contents = list(result.scalars().all())

    if not contents:
        return []

    detector = ImportanceDetector()
    clusters = detector.build_topic_clusters(contents)
    trending = [c for c in clusters if c.is_trending]

    response = []
    for cluster in trending[:limit]:
        best_content = max(cluster.contents, key=lambda c: c.published_at)
        topic_slug = None
        for content in cluster.contents:
            if content.topics:
                topic_slug = content.topics[0]
                break

        titles = [c.title for c in cluster.contents]
        keyword = _best_keyword(titles)
        response.append(
            TrendingTopicResponse(
                label=keyword.title() if keyword else best_content.title,
                keyword=keyword,
                article_count=len(cluster.contents),
                source_count=len(cluster.source_ids),
                topic_slug=topic_slug,
                theme=cluster.theme,
            )
        )

    logger.info(
        "trending_topics_served",
        total_contents=len(contents),
        trending_count=len(response),
    )
    return response
