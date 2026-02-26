"""Modèle DigestCompletion pour le suivi des digest complétés (Epic 10)."""

import uuid
from datetime import date, datetime
from typing import TYPE_CHECKING
from uuid import UUID

from sqlalchemy import Date, DateTime, Index, Integer, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base

if TYPE_CHECKING:
    pass  # No direct relationships


class DigestCompletion(Base):
    """Complétion d'un digest quotidien par un utilisateur.

    Enregistre quand un utilisateur termine son digest quotidien,
    avec des statistiques sur les actions effectuées (lu, sauvegardé, dismiss).
    Utilisé pour le calcul des streaks et les analytics d'engagement.

    Attributes:
        user_id: UUID de l'utilisateur.
        target_date: Date du digest complété.
        completed_at: Date/heure de complétion.
        articles_read: Nombre d'articles marqués comme lus.
        articles_saved: Nombre d'articles sauvegardés.
        articles_dismissed: Nombre d'articles marqués "pas intéressé".
        closure_time_seconds: Temps total en secondes depuis l'ouverture.
    """

    __tablename__ = "digest_completions"
    __table_args__ = (
        # Une seule complétion par (user, date)
        UniqueConstraint(
            "user_id", "target_date", name="uq_digest_completions_user_date"
        ),
        Index("ix_digest_completions_user_id", "user_id"),
        Index("ix_digest_completions_target_date", "target_date"),
        Index("ix_digest_completions_completed_at", "completed_at"),
    )

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), nullable=False)
    target_date: Mapped[date] = mapped_column(Date, nullable=False)
    completed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow, nullable=False
    )
    articles_read: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default="0"
    )
    articles_saved: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default="0"
    )
    articles_dismissed: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default="0"
    )
    closure_time_seconds: Mapped[int | None] = mapped_column(Integer, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow, nullable=False
    )
