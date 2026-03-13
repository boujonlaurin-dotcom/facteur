"""Schémas Pydantic pour la waitlist."""

from pydantic import BaseModel, EmailStr


class WaitlistRequest(BaseModel):
    """Requête d'inscription waitlist."""

    email: EmailStr
    source: str = "landing"


class WaitlistResponse(BaseModel):
    """Réponse inscription waitlist."""

    message: str
