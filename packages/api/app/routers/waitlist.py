"""Router waitlist — endpoint public pour inscription landing page."""

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.schemas.waitlist import WaitlistRequest, WaitlistResponse
from app.services.waitlist_service import WaitlistService

router = APIRouter()


@router.post("", response_model=WaitlistResponse)
async def join_waitlist(
    request: WaitlistRequest,
    db: AsyncSession = Depends(get_db),
) -> WaitlistResponse:
    """Inscription à la waitlist. Endpoint public, pas d'auth requise."""
    service = WaitlistService(db)
    await service.register(request.email, request.source)
    # Always return success — don't reveal if email already exists
    return WaitlistResponse(message="Merci ! On t'écrit très vite. 💌")
