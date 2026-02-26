"""Schemas abonnement."""

from datetime import datetime
from enum import StrEnum

from pydantic import BaseModel


class SubscriptionStatus(StrEnum):
    """Statuts d'abonnement."""

    TRIAL = "trial"
    ACTIVE = "active"
    EXPIRED = "expired"
    CANCELLED = "cancelled"


class SubscriptionResponse(BaseModel):
    """Réponse statut abonnement."""

    status: SubscriptionStatus
    trial_end: datetime | None = None
    current_period_end: datetime | None = None
    days_remaining: int
    is_premium: bool
    can_access: bool
    product_id: str | None = None


class RevenueCatWebhookEvent(BaseModel):
    """Événement webhook RevenueCat."""

    event: dict
    api_version: str
