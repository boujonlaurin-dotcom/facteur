"""Modèle UserLetterProgress — Lettres du Facteur (Story 19.1).

Une row par (user_id, letter_id). Les lettres elles-mêmes sont des constantes
Python (`app/services/letters/catalog.py`) — la DB stocke uniquement la
progression utilisateur.
"""

from datetime import UTC, datetime
from uuid import UUID

from sqlalchemy import (
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    PrimaryKeyConstraint,
    Text,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class UserLetterProgress(Base):
    """Progression d'un user sur une lettre du Facteur."""

    __tablename__ = "user_letter_progress"
    __table_args__ = (
        PrimaryKeyConstraint("user_id", "letter_id", name="pk_user_letter_progress"),
        CheckConstraint(
            "status IN ('upcoming', 'active', 'archived')",
            name="ck_user_letter_progress_status",
        ),
        Index(
            "ix_user_letter_progress_user_status",
            "user_id",
            "status",
        ),
    )

    user_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("user_profiles.user_id", ondelete="CASCADE"),
        nullable=False,
    )
    letter_id: Mapped[str] = mapped_column(Text, nullable=False)
    status: Mapped[str] = mapped_column(Text, nullable=False)
    completed_actions: Mapped[list[str]] = mapped_column(
        JSONB, nullable=False, server_default=text("'[]'::jsonb"), default=list
    )
    started_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    archived_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=text("now()"),
        default=lambda: datetime.now(UTC),
        onupdate=lambda: datetime.now(UTC),
    )
