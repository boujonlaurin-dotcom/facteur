from typing import List, Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user_id
from app.models.content import Content
from app.models.enums import ContentType, FeedFilterMode
from app.services.recommendation_service import RecommendationService
from app.schemas.content import ContentResponse, FeedResponse

router = APIRouter()

@router.get("/", response_model=FeedResponse)
async def get_personalized_feed(
    limit: int = Query(20, ge=1, le=50),
    offset: int = Query(0, ge=0),
    content_type: Optional[ContentType] = Query(None, alias="type"),
    mode: Optional[FeedFilterMode] = Query(None),
    saved_only: bool = Query(False, alias="saved"),
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """
    Récupère le feed personnalisé + le Top 3 (Briefing).
    """
    from datetime import datetime
    from sqlalchemy import select, and_
    from sqlalchemy.orm import selectinload
    
    from app.models.daily_top3 import DailyTop3
    from app.schemas.content import FeedResponse, DailyTop3Response

    service = RecommendationService(db)
    user_uuid = UUID(current_user_id)
    
    # 1. Get Feed Items
    feed_items = await service.get_feed(
        user_id=user_uuid, 
        limit=limit, 
        offset=offset,
        content_type=content_type,
        mode=mode,
        saved_only=saved_only
    )
    
    # 2. Get Today's Briefing (Only if offset=0 and basic feed mode)
    # On ne renvoie le briefing que sur la première page du feed général
    briefing_items = []
    if offset == 0 and not saved_only and mode is None and content_type is None:
        today_start = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
        
        stmt = (
            select(DailyTop3)
            .options(selectinload(DailyTop3.content).selectinload(Content.source))
            .where(
                DailyTop3.user_id == user_uuid,
                DailyTop3.generated_at >= today_start
            )
            .order_by(DailyTop3.rank)
        )
        briefing_result = await db.execute(stmt)
        briefing_rows = briefing_result.scalars().all()
        
        # Mapping ORM -> Schema
        # Note: DailyTop3Response expects 'content' field populated
        briefing_items = [
            DailyTop3Response(
                rank=row.rank,
                reason=row.top3_reason,
                consumed=row.consumed,
                content=row.content # Pydantic from_attributes will handle conversion to ContentResponse
            )
            for row in briefing_rows
        ]

    return FeedResponse(
        briefing=briefing_items,
        items=feed_items
    )


@router.post("/briefing/{content_id}/read", status_code=200)
async def mark_briefing_item_read(
    content_id: str,
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """Marque un item du briefing comme lu/consommé."""
    from datetime import datetime
    from sqlalchemy import select, update
    from app.models.daily_top3 import DailyTop3
    from app.services.contents_service import ContentsService # Hypothétique
    
    user_uuid = UUID(current_user_id)
    c_uuid = UUID(content_id)
    
    today_start = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
    
    # 1. Mark in DailyTop3
    stmt = (
        update(DailyTop3)
        .where(
            DailyTop3.user_id == user_uuid,
            DailyTop3.content_id == c_uuid,
            DailyTop3.generated_at >= today_start
        )
        .values(consumed=True)
    )
    await db.execute(stmt)
    
    # 2. Mark generic Content Status as SEEN (or CONSUMED?)
    # Briefing "read" might mostly mean "expanded/viewed".
    # Let's say it counts as CONSUMED if they opened it via this endpoint?
    # Or just SEEN?
    # Usually clicking the card -> open details -> API call to update status.
    # This endpoint specifically tracks "Briefing progress".
    # I'll let the client call the standard status endpoint separately if they want "Consumed" on content.
    # But for "Briefing" logic (progress bar 1/3, 2/3), this is specific.
    
    await db.commit()
    return {"message": "Briefing item marked as read"}
