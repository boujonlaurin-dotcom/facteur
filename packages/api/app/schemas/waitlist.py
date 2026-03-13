"""Schémas Pydantic pour la waitlist."""

from pydantic import BaseModel, EmailStr


class WaitlistRequest(BaseModel):
    """Requête d'inscription waitlist."""

    email: EmailStr
    source: str = "landing"
    utm_source: str | None = None
    utm_medium: str | None = None
    utm_campaign: str | None = None


class WaitlistResponse(BaseModel):
    """Réponse inscription waitlist."""

    message: str
    is_new: bool = True


class SurveyRequest(BaseModel):
    """Réponses au micro-survey post-signup."""

    email: EmailStr
    info_source: str
    main_pain: str
    willingness: str


class SurveyResponse(BaseModel):
    """Réponse soumission survey."""

    message: str
