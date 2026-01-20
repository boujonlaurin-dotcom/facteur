"""Modèles sources de contenu."""

import uuid
from datetime import datetime
from typing import Optional
from uuid import UUID

from sqlalchemy import Boolean, DateTime, Enum, ForeignKey, Index, String, Text
from sqlalchemy.dialects.postgresql import ARRAY, UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base
from app.models.enums import BiasOrigin, BiasStance, ReliabilityScore, SourceType


class Source(Base):
    """Source de contenu (RSS, podcast, YouTube)."""

    __tablename__ = "sources"
    __table_args__ = (
        Index("ix_sources_is_active", "is_active"),
        Index("ix_sources_is_curated", "is_curated"),
    )

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    url: Mapped[str] = mapped_column(Text, nullable=False)
    feed_url: Mapped[str] = mapped_column(Text, nullable=False, unique=True)
    type: Mapped[SourceType] = mapped_column(
        Enum(SourceType, values_callable=lambda x: [e.value for e in x], native_enum=False, length=20), nullable=False
    )
    theme: Mapped[str] = mapped_column(String(50), nullable=False)
    description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    logo_url: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    is_curated: Mapped[bool] = mapped_column(Boolean, default=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    last_synced_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    # Biais et fiabilité (Story 7.1)
    bias_stance: Mapped[BiasStance] = mapped_column(
        Enum(BiasStance, values_callable=lambda x: [e.value for e in x], native_enum=False, length=20),
        nullable=False,
        default=BiasStance.UNKNOWN,
        server_default=BiasStance.UNKNOWN.value,
    )
    reliability_score: Mapped[ReliabilityScore] = mapped_column(
        Enum(ReliabilityScore, values_callable=lambda x: [e.value for e in x], native_enum=False, length=20),
        nullable=False,
        default=ReliabilityScore.UNKNOWN,
        server_default=ReliabilityScore.UNKNOWN.value,
    )
    bias_origin: Mapped[BiasOrigin] = mapped_column(
        Enum(BiasOrigin, values_callable=lambda x: [e.value for e in x], native_enum=False, length=20),
        nullable=False,
        default=BiasOrigin.UNKNOWN,
        server_default=BiasOrigin.UNKNOWN.value,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow
    )

    # Scores granulaires (FQS Pillars - Story 7.5)
    score_independence: Mapped[Optional[float]] = mapped_column(nullable=True)
    score_rigor: Mapped[Optional[float]] = mapped_column(nullable=True)
    score_ux: Mapped[Optional[float]] = mapped_column(nullable=True)
    granular_topics: Mapped[Optional[list[str]]] = mapped_column(ARRAY(Text), nullable=True)
    
    # Daily Briefing (Story 4.4) - URL du feed "À la Une" pour les sources de référence
    une_feed_url: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

    # Relations
    contents: Mapped[list["Content"]] = relationship(
        "Content", back_populates="source", cascade="all, delete-orphan"
    )
    user_sources: Mapped[list["UserSource"]] = relationship(
        back_populates="source", cascade="all, delete-orphan"
    )


class UserSource(Base):
    """Association utilisateur-source."""

    __tablename__ = "user_sources"

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), nullable=False)
    source_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), ForeignKey("sources.id", ondelete="CASCADE")
    )
    is_custom: Mapped[bool] = mapped_column(Boolean, default=False)
    added_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow
    )

    # Relations
    source: Mapped["Source"] = relationship(back_populates="user_sources")


# Import pour éviter les circular imports
from app.models.content import Content  # noqa: E402, F401

