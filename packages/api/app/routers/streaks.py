"""Routes streak et progression."""

import time

import structlog
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user_id
from app.schemas.streak import StreakResponse
from app.services.streak_service import StreakService

router = APIRouter()
_perf_logger = structlog.get_logger("streak_perf")


@router.get("", response_model=StreakResponse)
async def get_streak(
    user_id: str = Depends(get_current_user_id),
    db: AsyncSession = Depends(get_db),
) -> StreakResponse:
    """Récupérer le streak et la progression."""
    t0 = time.monotonic()
    service = StreakService(db)
    streak = await service.get_streak(user_id)
    _perf_logger.info(
        "streak_handler_duration",
        duration_ms=round((time.monotonic() - t0) * 1000, 2),
        user_id=user_id,
    )

    return streak
