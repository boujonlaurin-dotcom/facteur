"""Modeles pour les preferences utilisateur sur entites nommees.

Historique : ce module contenait aussi `UserLearningProposal`, supprime
en Sprint 2 PR1 (feature morte). Cf. migration `lp02`.
"""

import uuid
from datetime import datetime
from uuid import UUID

from sqlalchemy import (
    DateTime,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class UserEntityPreference(Base):
    """Preference utilisateur sur une entite nommee (follow/mute)."""

    __tablename__ = "user_entity_preferences"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "entity_canonical",
            name="uq_user_entity_pref_user_entity",
        ),
    )

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), nullable=False)
    entity_canonical: Mapped[str] = mapped_column(Text, nullable=False)
    preference: Mapped[str] = mapped_column(String(10), nullable=False)  # follow | mute
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow
    )
