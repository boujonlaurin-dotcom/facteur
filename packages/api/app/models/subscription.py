"""Modèle abonnement."""

from datetime import datetime
from typing import Optional
from uuid import UUID

from sqlalchemy import DateTime, String
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
    revenuecat_user_id: Mapped[Optional[str]] = mapped_column(
        String(200), nullable=True
    )
    status: Mapped[str] = mapped_column(
        String(20), nullable=False, default="trial"
    )  # trial, active, expired, cancelled
    product_id: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    trial_start: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow
    )
    trial_end: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    current_period_start: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    current_period_end: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
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

