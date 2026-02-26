"""Routes streak et progression."""

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user_id
from app.schemas.streak import StreakResponse
from app.services.streak_service import StreakService

router = APIRouter()


@router.get("", response_model=StreakResponse)
async def get_streak(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> StreakResponse:
    """Récupérer le streak et la progression."""
    service = StreakService(db)
    streak = await service.get_streak(user_id)

    return streak
