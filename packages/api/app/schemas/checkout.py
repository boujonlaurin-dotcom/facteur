"""Schémas Pydantic pour le checkout web Premium."""

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, EmailStr, Field

# Longueur max d'un « mot » de soutien (aligné front + Stripe metadata <= 500).
SUPPORT_MESSAGE_MAX_LEN = 280


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


class CreateStripeSessionRequest(BaseModel):
    """Création d'une session Stripe Checkout à prix libre (appelé du web).

    Identité résolue soit via `token` signé (parcours app -> email -> web), soit
    via `email` (visiteur anonyme passwordless). `amount_cents` est borné serveur.
    """

    amount_cents: int
    token: str | None = None
    email: EmailStr | None = None
    # Mot optionnel laissé par le soutien (mur public, modéré avant affichage).
    message: str | None = Field(default=None, max_length=SUPPORT_MESSAGE_MAX_LEN)


class CreateStripeSessionResponse(BaseModel):
    """Réponse : URL hébergée Stripe Checkout vers laquelle rediriger."""

    url: str


class SupporterMessagePublic(BaseModel):
    """Message de soutien exposé publiquement (uniquement si `published`)."""

    message: str
    display_name: str | None = None
    created_at: datetime
