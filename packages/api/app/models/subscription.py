"""Modèle abonnement."""

from datetime import datetime, timedelta
from uuid import UUID, uuid4

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String, Text, func
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


# Source unique du vocabulaire de statut d'une livraison de lien de soutien.
# Consommé par la route (`_delivery_response`), le job de relance et le service
# pour éviter que les classifications « terminal » / « à réessayer » ne dérivent
# entre les fichiers.
SUPPORT_LINK_TERMINAL_STATUSES = frozenset(
    {"delivered", "bounced", "suppressed", "failed"}
)
SUPPORT_LINK_RETRYABLE_STATUSES = frozenset({"queued", "delayed"})
# Délai unique de la relance différée : le backoff d'envoi (service) et le
# webhook `email.delivery_delayed` doivent programmer exactement le même délai.
SUPPORT_LINK_RETRY_DELAY = timedelta(minutes=10)


class SupportLinkDelivery(Base):
    """Demande d'enveloppe de soutien suivie jusqu'à la remise fournisseur."""

    __tablename__ = "support_link_deliveries"

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid4
    )
    user_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), nullable=False, index=True
    )
    # Nécessaire à la relance différée; aucun token signé ni payload webhook
    # n'est persisté.
    recipient_email: Mapped[str] = mapped_column(String(320), nullable=False)
    status: Mapped[str] = mapped_column(String(32), nullable=False, default="queued")
    attempts: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    auto_retry_used: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False
    )
    next_retry_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    error_code: Mapped[str | None] = mapped_column(String(100))
    last_provider_event_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True)
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )


class SupportLinkDeliveryAttempt(Base):
    """Un message Resend par tentative, pour accepter les events tardifs."""

    __tablename__ = "support_link_delivery_attempts"

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid4
    )
    delivery_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("support_link_deliveries.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    attempt_number: Mapped[int] = mapped_column(Integer, nullable=False)
    provider_message_id: Mapped[str] = mapped_column(
        String(255), nullable=False, unique=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )


class ResendWebhookEvent(Base):
    """Déduplication durable des livraisons at-least-once de Resend."""

    __tablename__ = "resend_webhook_events"

    svix_id: Mapped[str] = mapped_column(String(255), primary_key=True)
    event_type: Mapped[str] = mapped_column(String(100), nullable=False)
    received_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
