from datetime import UTC, datetime, timedelta
from uuid import UUID

import structlog
from fastapi import APIRouter, Depends, Query
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
from app.schemas.learning import (
    LearningCheckpointResponse,
    proposal_to_response,
)
from app.services.learning_service import LearningService
from app.services.recommendation_service import RecommendationService

logger = structlog.get_logger()

router = APIRouter()


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
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """
    Récupère le feed personnalisé.

    Note: Le briefing (Top 3) a été déplacé vers l'endpoint dédié /api/digest.
    Le feed retourne uniquement les articles réguliers.
    """
    service = RecommendationService(db)
    user_uuid = UUID(current_user_id)

    # serein=True overrides mode to use the serein filter (same as INSPIRATION)
    if serein and not mode:
        mode = FeedFilterMode.INSPIRATION

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

    # Epic 13: Learning Checkpoint — include proposals on first page only
    checkpoint_data = None
    if offset == 0 and not saved_only:
        try:
            learning_service = LearningService(db)
            proposals = await learning_service.get_pending_proposals(user_uuid)
            if len(proposals) >= 2:
                checkpoint_data = LearningCheckpointResponse(
                    proposals=[proposal_to_response(p) for p in proposals],
                    total_pending=len(proposals),
                )
                await db.commit()
        except Exception as e:
            logger.warning("learning_checkpoint_error", error=str(e))

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
        learning_checkpoint=checkpoint_data,
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


@router.get("/trending-topics", response_model=list[TrendingTopicResponse])
async def get_trending_topics(
    limit: int = Query(8, ge=1, le=20),
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Retourne les sujets tendance du moment (clusters multi-sources des dernières 24h)."""
    from sqlalchemy import select

    from app.models.content import Content
    from app.services.briefing.importance_detector import ImportanceDetector

    cutoff = datetime.now(UTC) - timedelta(hours=24)
    stmt = (
        select(Content)
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

        response.append(
            TrendingTopicResponse(
                label=best_content.title,
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
