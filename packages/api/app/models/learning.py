"""Modeles pour les preferences utilisateur sur entites nommees.

Historique : ce module contenait aussi `UserLearningProposal`, supprime
en Sprint 2 PR1 (feature morte). Cf. migration `lp02`.
"""

import uuid
from datetime import datetime
from uuid import UUID

from sqlalchemy import (
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
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


class UserEntityAffinity(Base):
    """Affinite positive apprise sur une entite nommee (PR2 « le levier »).

    Miroir exact de la boucle sujets (`UserSubtopic`) cote entites : chaque
    interaction (lecture/like/save/note/hide) deplace `affinity` autour du
    neutre 1.0, borne [0.1, 3.0], avec decay quotidien vers 1.0. Le pilier
    Pertinence recompense `affinity > 1.0` (entite lue souvent), de facon
    plafonnee pour ne pas tuer la diversite. Distinct de
    `UserEntityPreference` (follow/mute binaire, signal explicite).
    """

    __tablename__ = "user_entity_affinity"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "entity_canonical",
            name="uq_user_entity_affinity_user_entity",
        ),
        Index("ix_user_entity_affinity_user_id", "user_id"),
    )

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("user_profiles.user_id", ondelete="CASCADE"),
        nullable=False,
    )
    entity_canonical: Mapped[str] = mapped_column(Text, nullable=False)
    affinity: Mapped[float] = mapped_column(Float, default=1.0, nullable=False)
    interaction_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=datetime.utcnow,
        onupdate=datetime.utcnow,
    )
