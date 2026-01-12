from typing import List, Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user_id
from app.models.content import Content
from app.models.enums import ContentType, FeedFilterMode
from app.services.recommendation_service import RecommendationService
from app.schemas.content import ContentResponse

router = APIRouter()

@router.get("/", response_model=List[ContentResponse])
async def get_personalized_feed(
    limit: int = Query(20, ge=1, le=50),
    offset: int = Query(0, ge=0),
    content_type: Optional[ContentType] = Query(None, alias="type"), # Deprecated but kept for compat
    mode: Optional[FeedFilterMode] = Query(None),
    saved_only: bool = Query(False, alias="saved"),
    db: AsyncSession = Depends(get_db),
    current_user_id: str = Depends(get_current_user_id),
):
    """
    Récupère le feed personnalisé de l'utilisateur connecté.
    
    L'algorithme de tri prend en compte :
    - Les centres d'intérêt (Thèmes)
    - Les abonnements aux sources
    - La fraîcheur du contenu
    - L'historique (contenus vus exclus)
    - Le filtre par type (Optionnel)
    """
    service = RecommendationService(db)
    # Convert string ID from JWT to UUID
    user_uuid = UUID(current_user_id)
    
    feed = await service.get_feed(
        user_id=user_uuid, 
        limit=limit, 
        offset=offset,
        content_type=content_type,
        mode=mode,
        saved_only=saved_only
    )
    return feed
