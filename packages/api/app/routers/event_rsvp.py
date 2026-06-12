"""Router RSVP événement — endpoint public pour confirmer sa présence.

Distinct de la waitlist : capture de façon fiable chaque participant (table
`event_rsvps`), y compris les emails déjà présents dans la waitlist. Le RSVP
ajoute aussi la personne à la waitlist (source = event_slug) pour qu'elle
reçoive la notif de lancement.
"""

import hashlib

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.schemas.event_rsvp import (
    EventRsvpCountResponse,
    EventRsvpRequest,
    EventRsvpResponse,
)
from app.services.event_rsvp_service import EventRsvpService
from app.services.posthog_client import get_posthog_client
from app.services.waitlist_service import WaitlistService

router = APIRouter()


def _email_distinct_id(email: str) -> str:
    """Distinct_id stable pour un lead non authentifié (hash de l'email)."""
    return "lead_" + hashlib.sha256(email.strip().lower().encode()).hexdigest()[:16]


@router.get("/{event_slug}/rsvp/count", response_model=EventRsvpCountResponse)
async def get_rsvp_count(
    event_slug: str,
    db: AsyncSession = Depends(get_db),
) -> EventRsvpCountResponse:
    """Nombre de RSVP pour un événement (public, pour la jauge)."""
    service = EventRsvpService(db)
    count = await service.get_count(event_slug)
    return EventRsvpCountResponse(event_slug=event_slug, count=count)


@router.post("/rsvp", response_model=EventRsvpResponse)
async def rsvp(
    request: EventRsvpRequest,
    db: AsyncSession = Depends(get_db),
) -> EventRsvpResponse:
    """Confirme la présence à un événement. Endpoint public, pas d'auth.

    Enregistre le RSVP (table dédiée) puis ajoute l'email à la waitlist pour la
    notif de lancement. L'ajout waitlist est best-effort : un échec ne doit pas
    faire échouer le RSVP lui-même.
    """
    rsvp_service = EventRsvpService(db)
    is_new = await rsvp_service.register(
        request.email,
        event_slug=request.event_slug,
        utm_source=request.utm_source,
        utm_medium=request.utm_medium,
        utm_campaign=request.utm_campaign,
    )

    # Ajoute aussi à la waitlist (source = slug de l'événement) pour la notif de
    # lancement. Best-effort : indépendant du succès du RSVP.
    waitlist_service = WaitlistService(db)
    await waitlist_service.register(
        request.email,
        source=request.event_slug,
        utm_source=request.utm_source,
        utm_medium=request.utm_medium,
        utm_campaign=request.utm_campaign,
    )

    if is_new:
        get_posthog_client().capture(
            user_id=_email_distinct_id(request.email),
            event="event_rsvp",
            properties={
                "event_slug": request.event_slug,
                "utm_source": request.utm_source,
                "utm_medium": request.utm_medium,
                "utm_campaign": request.utm_campaign,
            },
        )

    count = await rsvp_service.get_count(request.event_slug)
    return EventRsvpResponse(
        message="Génial, on t'attend ! 🎉",
        is_new=is_new,
        rsvp_count=count,
    )
