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
    """Action de l'utilisateur sur la modal d'invitation.

    - "accepted" : a cliqué pour réserver un créneau (terminal).
    - "declined" : "Plus tard" (snooze, puis terminal après MAX_SHOWS).
    - "already_done" : "On l'a déjà fait" (terminal, plus jamais sollicité).
    """

    action: str = Field(..., pattern=r"^(accepted|declined|already_done)$")
