"""Modèle des préférences de notifications push d'un utilisateur."""

from datetime import datetime
from uuid import UUID

from sqlalchemy import Boolean, CheckConstraint, DateTime, ForeignKey, Integer, Text
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class UserNotificationPreferences(Base):
    """Préférences notifications push (préset, heure, état refus/re-nudge)."""

    __tablename__ = "user_notification_preferences"

    user_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("user_profiles.user_id", ondelete="CASCADE"),
        primary_key=True,
    )

    push_enabled: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )
    preset: Mapped[str] = mapped_column(
        Text, nullable=False, default="minimaliste", server_default="minimaliste"
    )
    time_slot: Mapped[str] = mapped_column(
        Text, nullable=False, default="morning", server_default="morning"
    )
    timezone: Mapped[str] = mapped_column(
        Text, nullable=False, default="Europe/Paris", server_default="Europe/Paris"
    )

    refusal_count: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default="0"
    )
    last_refusal_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    last_renudge_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    renudge_shown_count: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default="0"
    )
    modal_seen: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow
    )

    __table_args__ = (
        CheckConstraint(
            "preset IN ('minimaliste', 'curieux')",
            name="user_notif_prefs_preset_check",
        ),
        CheckConstraint(
            "time_slot IN ('morning', 'evening')",
            name="user_notif_prefs_time_slot_check",
        ),
    )
