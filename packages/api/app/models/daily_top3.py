"""Modèle DailyTop3 pour le briefing quotidien."""

import uuid
from datetime import datetime
from typing import TYPE_CHECKING
from uuid import UUID

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    text,
)
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base

if TYPE_CHECKING:
    from app.models.content import Content


class DailyTop3(Base):
    """Top 3 articles quotidiens d'un utilisateur.

    Génération quotidienne à 8h Paris. Chaque utilisateur reçoit 3 articles
    sélectionnés selon l'importance objective et la pertinence personnalisée.

    Attributes:
        user_id: UUID de l'utilisateur.
        content_id: UUID de l'article sélectionné.
        rank: Position dans le Top 3 (1, 2 ou 3).
        top3_reason: Raison de sélection ("À la Une", "Sujet tendance", "Source suivie").
        consumed: True si l'utilisateur a lu cet article.
        generated_at: Date/heure de génération du briefing.
    """

    __tablename__ = "daily_top3"
    __table_args__ = (
        # Une seule entrée par (user, rank, date)
        Index("ix_daily_top3_user_date", "user_id", "generated_at"),
        CheckConstraint("rank >= 1 AND rank <= 3", name="ck_daily_top3_rank_range"),
        # Unique constraint on (user_id, rank, DATE(generated_at AT TIME ZONE 'UTC'))
        Index(
            "uq_daily_top3_user_rank_day",
            "user_id",
            "rank",
            text("date(generated_at AT TIME ZONE 'UTC')"),
            unique=True,
        ),
    )

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), nullable=False, index=True
    )
    content_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("contents.id", ondelete="CASCADE"),
        nullable=False,
    )
    rank: Mapped[int] = mapped_column(Integer, nullable=False)
    top3_reason: Mapped[str] = mapped_column(String(100), nullable=False)
    consumed: Mapped[bool] = mapped_column(
        Boolean, default=False, server_default="false"
    )
    generated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow, nullable=False
    )

    # Relations
    content: Mapped["Content"] = relationship()
