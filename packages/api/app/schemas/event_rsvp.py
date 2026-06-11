"""Schémas Pydantic pour les RSVP événement."""

from pydantic import BaseModel, EmailStr


class EventRsvpRequest(BaseModel):
    """Requête de confirmation de présence à un événement."""

    email: EmailStr
    event_slug: str = "soiree-prelancement"
    utm_source: str | None = None
    utm_medium: str | None = None
    utm_campaign: str | None = None


class EventRsvpResponse(BaseModel):
    """Réponse à une confirmation de présence."""

    message: str
    is_new: bool = True
    rsvp_count: int


class EventRsvpCountResponse(BaseModel):
    """Nombre de RSVP pour un événement (public, pour la jauge)."""

    event_slug: str
    count: int
