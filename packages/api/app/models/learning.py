"""Modeles pour le Learning Checkpoint (Epic 13)."""

import uuid
from datetime import datetime
from uuid import UUID

from sqlalchemy import (
    DateTime,
    Float,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class UserLearningProposal(Base):
    """Proposition d'ajustement generee par l'algorithme d'apprentissage."""

    __tablename__ = "user_learning_proposals"
    __table_args__ = (
        Index(
            "idx_learning_proposals_user_pending",
            "user_id",
            "status",
            postgresql_where="status = 'pending'",
        ),
    )

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), nullable=False)

    # Type de proposition
    proposal_type: Mapped[str] = mapped_column(
        String(30), nullable=False
    )  # source_priority | follow_entity | mute_entity

    # Entite cible (polymorphe)
    entity_type: Mapped[str] = mapped_column(
        String(20), nullable=False
    )  # source | entity
    entity_id: Mapped[str] = mapped_column(
        Text, nullable=False
    )  # UUID pour source, nom canonique pour entite
    entity_label: Mapped[str] = mapped_column(Text, nullable=False)  # Nom affichable

    # Valeurs
    current_value: Mapped[str | None] = mapped_column(Text, nullable=True)
    proposed_value: Mapped[str] = mapped_column(Text, nullable=False)

    # Signal
    signal_strength: Mapped[float] = mapped_column(Float, nullable=False)
    signal_context: Mapped[dict] = mapped_column(JSONB, nullable=False)

    # Lifecycle
    shown_count: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    status: Mapped[str] = mapped_column(
        String(20), default="pending", server_default="pending"
    )  # pending | accepted | modified | dismissed | expired
    user_chosen_value: Mapped[str | None] = mapped_column(Text, nullable=True)

    # Timestamps
    computed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow
    )
    shown_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    resolved_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow
    )


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
