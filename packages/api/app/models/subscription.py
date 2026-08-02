"""Modèle abonnement."""

from datetime import datetime
from uuid import UUID

from sqlalchemy import Boolean, DateTime, Integer, String, Text, func
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class UserSubscription(Base):
    """Abonnement premium utilisateur."""

    __tablename__ = "user_subscriptions"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True)
    user_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), unique=True, nullable=False
    )
    revenuecat_user_id: Mapped[str | None] = mapped_column(String(200), nullable=True)
    status: Mapped[str] = mapped_column(
        String(20), nullable=False, default="trial"
    )  # trial, active, expired, cancelled
    product_id: Mapped[str | None] = mapped_column(String(100), nullable=True)
    trial_start: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow
    )
    trial_end: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    current_period_start: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    current_period_end: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    last_event_id: Mapped[str | None] = mapped_column(String(100), nullable=True)
    # Miroir Stripe (parcours « Soutien à prix libre »). NULL pour l'existant
    # RevenueCat ; `provider` vaut 'stripe' pour les abonnements Stripe.
    stripe_customer_id: Mapped[str | None] = mapped_column(String(255), nullable=True)
    stripe_subscription_id: Mapped[str | None] = mapped_column(
        String(255), nullable=True
    )
    support_amount_cents: Mapped[int | None] = mapped_column(Integer, nullable=True)
    provider: Mapped[str | None] = mapped_column(String(20), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow
    )

    @property
    def is_active(self) -> bool:
        """Vérifie si l'abonnement est actif."""
        if self.status in ("active", "trial"):
            if self.status == "trial":
                return datetime.utcnow() < self.trial_end
            elif self.current_period_end:
                return datetime.utcnow() < self.current_period_end
        return False

    @property
    def days_remaining(self) -> int:
        """Jours restants avant expiration."""
        if self.status == "trial":
            delta = self.trial_end - datetime.utcnow()
            return max(0, delta.days)
        elif self.status == "active" and self.current_period_end:
            delta = self.current_period_end - datetime.utcnow()
            return max(0, delta.days)
        return 0


class StripeEvent(Base):
    """Idempotence globale des webhooks Stripe.

    Le handler insère `event_id` en `ON CONFLICT DO NOTHING` avant de traiter :
    un événement déjà vu (retry Stripe sur réponse non-2xx) est ignoré, ce qui
    évite un double grant RevenueCat.
    """

    __tablename__ = "stripe_events"

    event_id: Mapped[str] = mapped_column(String(255), primary_key=True)
    event_type: Mapped[str | None] = mapped_column(String(100), nullable=True)
    received_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )


class SupporterMessage(Base):
    """Mot laissé par un soutien, destiné à un mur public (modéré).

    Persisté au webhook `checkout.session.completed` (paiement engagé).
    `published` reste False tant qu'un humain n'a pas validé le message : rien
    n'apparaît publiquement sans modération.
    """

    __tablename__ = "supporter_messages"

    id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), primary_key=True)
    user_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True), nullable=True)
    message: Mapped[str] = mapped_column(Text, nullable=False)
    display_name: Mapped[str | None] = mapped_column(String(120), nullable=True)
    stripe_session_id: Mapped[str | None] = mapped_column(String(255), nullable=True)
    published: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default="false", default=False
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
