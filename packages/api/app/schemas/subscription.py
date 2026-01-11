"""Schemas abonnement."""

from datetime import datetime
from enum import Enum
from typing import Optional

from pydantic import BaseModel


class SubscriptionStatus(str, Enum):
    """Statuts d'abonnement."""

    TRIAL = "trial"
    ACTIVE = "active"
    EXPIRED = "expired"
    CANCELLED = "cancelled"


class SubscriptionResponse(BaseModel):
    """Réponse statut abonnement."""

    status: SubscriptionStatus
    trial_end: Optional[datetime] = None
    current_period_end: Optional[datetime] = None
    days_remaining: int
    is_premium: bool
    can_access: bool
    product_id: Optional[str] = None


class RevenueCatWebhookEvent(BaseModel):
    """Événement webhook RevenueCat."""

    event: dict
    api_version: str

