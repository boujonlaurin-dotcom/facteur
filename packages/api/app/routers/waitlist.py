"""Router waitlist — endpoint public pour inscription landing page."""

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.schemas.waitlist import (
    SurveyRequest,
    SurveyResponse,
    WaitlistCountResponse,
    WaitlistRequest,
    WaitlistResponse,
)
from app.services.waitlist_service import WaitlistService

router = APIRouter()


@router.get("/count", response_model=WaitlistCountResponse)
async def get_waitlist_count(
    db: AsyncSession = Depends(get_db),
) -> WaitlistCountResponse:
    """Nombre d'inscrits waitlist. Endpoint public."""
    service = WaitlistService(db)
    count = await service.get_count()
    return WaitlistCountResponse(count=count)


@router.post("", response_model=WaitlistResponse)
async def join_waitlist(
    request: WaitlistRequest,
    db: AsyncSession = Depends(get_db),
) -> WaitlistResponse:
    """Inscription à la waitlist. Endpoint public, pas d'auth requise."""
    service = WaitlistService(db)
    is_new = await service.register(
        request.email,
        request.source,
        utm_source=request.utm_source,
        utm_medium=request.utm_medium,
        utm_campaign=request.utm_campaign,
    )
    return WaitlistResponse(
        message="Merci ! On t'écrit très vite. 💌",
        is_new=is_new,
    )


@router.post("/survey", response_model=SurveyResponse)
async def submit_survey(
    request: SurveyRequest,
    db: AsyncSession = Depends(get_db),
) -> SurveyResponse:
    """Soumission du micro-survey post-signup. Endpoint public."""
    service = WaitlistService(db)
    await service.submit_survey(
        email=request.email,
        info_source=request.info_source,
        main_pain=request.main_pain,
        willingness=request.willingness,
    )
    # Always return success — don't reveal internal state
    return SurveyResponse(message="Merci pour tes réponses !")
