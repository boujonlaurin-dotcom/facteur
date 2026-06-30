"""Modèles pour le système de feedback utilisateur (Epic 13).

- DigestSentiment : micro-feedback emoji (😴/🙂/🔥) capturé au moment de
  fermeture, une réponse par (user, jour), en upsert.
- FeedbackInvite : état de l'invitation à un call qualitatif (Calendly).
  Pilote l'affichage unique/segmenté de la modal côté mobile.
"""

import uuid
from datetime import date, datetime
from uuid import UUID

from sqlalchemy import Date, DateTime, Index, Integer, String, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class DigestSentiment(Base):
    """Ressenti emoji d'un utilisateur sur son digest du jour.

    Capté au moment de fermeture. Trois niveaux : "low" (😴), "ok" (🙂),
    "high" (🔥). Une seule réponse par (user, jour) — l'utilisateur peut
    changer d'avis (upsert).

    Attributes:
        user_id: UUID de l'utilisateur.
        digest_date: Date du digest noté.
        sentiment: Ressenti ("low" | "ok" | "high").
    """

    __tablename__ = "digest_sentiments"
    __table_args__ = (
        UniqueConstraint(
            "user_id", "digest_date", name="uq_digest_sentiments_user_date"
        ),
        Index("ix_digest_sentiments_user_id", "user_id"),
        Index("ix_digest_sentiments_digest_date", "digest_date"),
    )

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), nullable=False)
    digest_date: Mapped[date] = mapped_column(Date, nullable=False)
    sentiment: Mapped[str] = mapped_column(String(10), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )


class FeedbackInvite(Base):
    """État de l'invitation à un call qualitatif pour un utilisateur.

    Une ligne par utilisateur. Pilote l'affichage segmenté et unique de la
    modal Calendly côté mobile (cf. story 13.1).

    Attributes:
        user_id: UUID de l'utilisateur (unique).
        status: "pending" | "snoozed" | "accepted" | "declined".
        segment: Segment d'activité au moment du déclenchement
            ("returning" | "low_active" | "active").
        shown_count: Nombre de fois où la modal a été affichée.
        last_shown_at: Dernier affichage.
        snoozed_until: Ne pas re-proposer avant cette date (snooze "Pas maintenant").
    """

    __tablename__ = "feedback_invites"
    __table_args__ = (
        UniqueConstraint("user_id", name="uq_feedback_invites_user"),
    )

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), nullable=False)
    status: Mapped[str] = mapped_column(
        String(20), nullable=False, default="pending", server_default="pending"
    )
    segment: Mapped[str | None] = mapped_column(String(20), nullable=True)
    shown_count: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default="0"
    )
    last_shown_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    snoozed_until: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
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
