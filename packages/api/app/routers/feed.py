from datetime import UTC, datetime, timedelta
from uuid import UUID

import structlog
from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user_id
from app.models.content import UserContentStatus
from app.models.enums import ContentType, FeedFilterMode
from app.schemas.content import FeedRefreshRequest
from app.schemas.feed import FeedResponse, PaginationMeta
from app.services.recommendation_service import RecommendationService

logger = structlog.get_logger()

router = APIRouter()


@router.get("/", response_model=FeedResponse)
async def get_personalized_feed(
    limit: int = Query(20, ge=1, le=50),
    offset: int = Query(0, ge=0),
    content_type: ContentType | None = Query(None, alias="type"),
    mode: FeedFilterMode | None = Query(None),
    theme: str | None = Query(
        None, description="Theme slug to filter by (e.g. 'tech', 'science')"
    ),
    saved_only: bool = Query(False, alias="saved"),
    has_note: bool = Query(False, alias="has_note"),
    source_id: str | None = Query(None, description="Source UUID to filter by"),
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

    # Get Feed Items only - briefing moved to dedicated digest endpoint
    feed_items = await service.get_feed(
        user_id=user_uuid,
        limit=limit,
        offset=offset,
        content_type=content_type,
        mode=mode,
        saved_only=saved_only,
        theme=theme,
    )

    # Calculate pagination metadata
    # If we got 'limit' items, assume there's a next page
    has_next = len(feed_items) >= limit

    return FeedResponse(
        items=feed_items,
        pagination=PaginationMeta(
            page=(offset // limit) + 1,
            per_page=limit,
            total=0,  # Total unknown without additional query
            has_next=has_next,
        ),
    )


@router.post("/refresh", status_code=200)
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
    """
    from app.models.enums import ContentStatus
    from sqlalchemy.dialects.postgresql import insert

    user_uuid = UUID(current_user_id)
    now = datetime.now(UTC)
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
    return {"refreshed": refreshed}


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
