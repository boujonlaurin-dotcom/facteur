"""Router waitlist — endpoint public pour inscription landing page."""

import hashlib

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
from app.services.posthog_client import get_posthog_client
from app.services.waitlist_service import WaitlistService

router = APIRouter()


def _email_distinct_id(email: str) -> str:
    """Distinct_id stable pour un lead non authentifié (hash de l'email).

    On ne push pas l'email en clair à PostHog — on déterministe un id qui
    pourra être alias'é au vrai user_id après signup côté mobile.
    """
    return "lead_" + hashlib.sha256(email.strip().lower().encode()).hexdigest()[:16]


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
    if is_new:
        get_posthog_client().capture(
            user_id=_email_distinct_id(request.email),
            event="waitlist_signup",
            properties={
                "source": request.source,
                "utm_source": request.utm_source,
                "utm_medium": request.utm_medium,
                "utm_campaign": request.utm_campaign,
            },
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
