"""Schemas Pydantic pour le système de feedback utilisateur (Epic 13)."""

from pydantic import BaseModel, Field


class SentimentRequest(BaseModel):
    """Micro-feedback emoji sur le digest du jour."""

    sentiment: str = Field(..., pattern=r"^(low|ok|high)$")
    digest_date: str | None = None


class FeedbackInviteStatus(BaseModel):
    """Réponse indiquant si la modal d'invitation au call doit s'afficher."""

    should_show: bool
    segment: str | None = None
    reason: str | None = None


class InviteActionRequest(BaseModel):
    """Action de l'utilisateur sur la modal d'invitation."""

    action: str = Field(..., pattern=r"^(accepted|declined)$")
