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
    
    # --- 1. Top 3 (Briefing) ---
    briefing_items = []
    
    # On ne récupère le briefing que sur la première page par défaut
    if offset == 0:
        from app.services.briefing_service import BriefingService
        briefing_service = BriefingService(db)
        # Lazy Generation : Récupère ou génère si absent
        briefing_dicts = await briefing_service.get_or_create_briefing(current_user_id)
        
        # Le service retourne des dicts, on les utilise pour le FeedResponse
        briefing_items = briefing_dicts

    # Récupérer les IDs des contenus du briefing pour exclusion
    briefing_content_ids = [item['content_id'] for item in briefing_items]
    
    # 2. Get Feed Items
    feed_items = await service.get_feed(
        user_id=user_uuid, 
        limit=limit, 
        offset=offset,
        content_type=content_type,
        mode=mode,
        saved_only=saved_only
    )
    
    # PERFORMANCE OPTIMIZATION: Exclure les items du briefing du feed sil ne l'ont pas déjà été
    # (Le service de recommandation pourrait les inclure par défaut)
    if briefing_content_ids:
        feed_items = [item for item in feed_items if item.id not in briefing_content_ids]

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
    from datetime import datetime, timedelta
    from sqlalchemy import select, update
    from app.models.daily_top3 import DailyTop3
    
    user_uuid = UUID(current_user_id)
    c_uuid = UUID(content_id)
    
    # FIX: Broaden window to last 48h to avoid timezone edge cases
    # (e.g. Generated at 23:00 UTC previous day)
    lookback_window = datetime.utcnow() - timedelta(hours=48)
    
    # 1. Mark in DailyTop3
    stmt = (
        update(DailyTop3)
        .where(
            DailyTop3.user_id == user_uuid,
            DailyTop3.content_id == c_uuid,
            DailyTop3.generated_at >= lookback_window
        )
        .values(consumed=True)
    )
    result = await db.execute(stmt)
    await db.commit()
    
    if result.rowcount == 0:
        print(f"⚠️ [WARNING] No DailyTop3 item found to mark as read for user {user_uuid} and content {c_uuid}")
    else:
        print(f"✅ [SUCCESS] Marked {result.rowcount} DailyTop3 items as read for user {user_uuid}")

    return {"message": "Briefing item marked as read", "updated": result.rowcount}
