"""Router pour la note self-reported "bien informé" (Story 14.3)."""

from uuid import UUID

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user_id
from app.schemas.well_informed import WellInformedRatingCreate, WellInformedRatingRead
from app.services.well_informed_service import submit_rating

router = APIRouter(tags=["WellInformed"])


@router.post("/ratings", response_model=WellInformedRatingRead, status_code=201)
async def create_rating(
    payload: WellInformedRatingCreate,
    device_id: str | None = None,
    user_id: UUID = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> WellInformedRatingRead:
    """Enregistre la note 1-10 de l'utilisateur."""
    rating = await submit_rating(db, user_id, payload, device_id=device_id)
    return WellInformedRatingRead.model_validate(rating)
