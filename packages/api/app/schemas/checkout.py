"""Schémas Pydantic pour le checkout web Premium."""

from typing import Literal

from pydantic import BaseModel, EmailStr


class CheckoutStartRequest(BaseModel):
    """Démarrage du flow de checkout depuis la landing."""

    email: EmailStr
    offering: Literal["default", "founder"] = "default"
    utm_source: str | None = None
    utm_medium: str | None = None
    utm_campaign: str | None = None


class CheckoutStartResponse(BaseModel):
    """Réponse : user_id Supabase + URL de checkout RevenueCat Web Billing."""

    user_id: str
    checkout_url: str
    is_new_user: bool


class CheckoutSendLinkRequest(BaseModel):
    """Envoi du lien de checkout par email (magic link Supabase)."""

    offering: Literal["default", "founder"] = "default"
    resend: bool = False


class CheckoutSendLinkResponse(BaseModel):
    """Réponse : confirmation d'envoi + email masquable côté client."""

    sent: bool
    email: EmailStr
