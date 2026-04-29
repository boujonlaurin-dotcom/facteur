"""Self-reported "well-informed" score (1-10) — Story 14.3."""

import uuid
from datetime import datetime
from uuid import UUID

from sqlalchemy import CheckConstraint, DateTime, Index, Integer, String
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class UserWellInformedRating(Base):
    """Note 1-10 auto-reportée par l'utilisateur ("à quel point te sens-tu bien
    informé ?") soumise via un prompt inline dans le digest (cooldown 14j si
    répondu, 5j si skippé — côté client).

    Source de vérité longitudinale (cohortes, moyenne, évolution). L'event
    PostHog `well_informed_score_submitted` est miroité pour les dashboards et
    le funnel (shown / skipped / submitted).
    """

    __tablename__ = "user_well_informed_ratings"
    __table_args__ = (
        CheckConstraint(
            "score >= 1 AND score <= 10",
            name="ck_well_informed_ratings_score_range",
        ),
        Index("ix_well_informed_ratings_user_id", "user_id"),
        Index("ix_well_informed_ratings_submitted_at", "submitted_at"),
    )

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), nullable=False)
    score: Mapped[int] = mapped_column(Integer, nullable=False)
    context: Mapped[str] = mapped_column(
        String(32), nullable=False, default="digest_inline"
    )
    device_id: Mapped[str | None] = mapped_column(String(255), nullable=True)
    submitted_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow, nullable=False
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow, nullable=False
    )
