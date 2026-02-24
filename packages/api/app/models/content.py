"""Modèles contenus."""

import uuid
from datetime import datetime
from typing import TYPE_CHECKING, Optional
from uuid import UUID

from sqlalchemy import Boolean, DateTime, Enum, ForeignKey, Index, Integer, String, Text, UniqueConstraint
from sqlalchemy.dialects.postgresql import ARRAY, UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base
from app.models.enums import ContentStatus, ContentType

if TYPE_CHECKING:
    from app.models.classification_queue import ClassificationQueue
    from app.models.source import Source


class Content(Base):
    """Contenu individuel (article, épisode podcast, vidéo)."""

    __tablename__ = "contents"
    __table_args__ = (
        Index("ix_contents_guid", "guid"),
        Index("ix_contents_published_at", "published_at"),
        Index("ix_contents_source_id", "source_id"),
        # Performance indexes for digest optimization
        # Composite index for Content queries ordered by published_at with source_id
        Index("ix_contents_source_published", "source_id", "published_at"),
        # Partial index for Emergency Fallback on curated sources
        # Note: Partial index condition handled in migration
        Index("ix_contents_curated_published", "published_at", "source_id"),
        # Composite index for theme-filtered queries with ORDER BY published_at DESC
        # Replaces single-column ix_contents_theme (composite is a strict superset)
        Index("ix_contents_theme_published", "theme", "published_at"),
    )

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    source_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), ForeignKey("sources.id", ondelete="CASCADE")
    )
    title: Mapped[str] = mapped_column(String(500), nullable=False)
    url: Mapped[str] = mapped_column(Text, nullable=False)
    thumbnail_url: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    published_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
    duration_seconds: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    content_type: Mapped[ContentType] = mapped_column(
        Enum(ContentType, values_callable=lambda x: [e.value for e in x], native_enum=False, length=20), nullable=False
    )
    guid: Mapped[str] = mapped_column(String(500), nullable=False)
    # Story 5.2: In-App Reading Mode
    html_content: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    audio_url: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    # Story clustering (Story 7.2)
    cluster_id: Mapped[Optional[UUID]] = mapped_column(
        PGUUID(as_uuid=True), nullable=True, index=True
    )
    # Story 4.1c: Granular topic tagging
    topics: Mapped[Optional[list[str]]] = mapped_column(ARRAY(Text), nullable=True)
    # Thème inféré par ML à partir du titre/description (Phase 2 diversité feed)
    # Slug normalisé dérivé du top topic classifié (tech, society, etc.)
    theme: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    # Story 4.2-US-4: Named Entity Recognition
    # entities: Mapped[Optional[list[str]]] = mapped_column(ARRAY(Text), nullable=True)
    # Paywall detection: whether article is behind a paywall
    is_paid: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow
    )

    # Relations
    source: Mapped["Source"] = relationship(back_populates="contents")
    user_statuses: Mapped[list["UserContentStatus"]] = relationship(
        back_populates="content", cascade="all, delete-orphan"
    )
    classification_queue: Mapped[Optional["ClassificationQueue"]] = relationship(
        back_populates="content", uselist=False, cascade="all, delete-orphan"
    )


class UserContentStatus(Base):
    """Statut d'un contenu pour un utilisateur."""

    __tablename__ = "user_content_status"
    __table_args__ = (
        UniqueConstraint("user_id", "content_id", name="uq_user_content_status_user_content"),
        Index("ix_user_content_status_user_saved", "user_id", "is_saved"),
        Index("ix_user_content_status_user_liked", "user_id", "is_liked"),
        Index("ix_user_content_status_user_status", "user_id", "status"),
        # Performance index for digest exclusion queries
        # Used in _get_candidates() EXISTS subquery that filters out seen/saved/hidden content
        Index("ix_user_content_status_exclusion", "user_id", "content_id", "is_hidden", "is_saved", "status"),
    )

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), nullable=False)
    content_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), ForeignKey("contents.id", ondelete="CASCADE")
    )
    status: Mapped[ContentStatus] = mapped_column(
        Enum(ContentStatus, values_callable=lambda x: [e.value for e in x], native_enum=False, length=20),
        nullable=False,
        default=ContentStatus.UNSEEN,
    )
    is_saved: Mapped[bool] = mapped_column(default=False, server_default="false")
    is_liked: Mapped[bool] = mapped_column(default=False, server_default="false")
    is_hidden: Mapped[bool] = mapped_column(default=False, server_default="false")
    hidden_reason: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    seen_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    time_spent_seconds: Mapped[int] = mapped_column(Integer, default=0)
    saved_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    liked_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    note_text: Mapped[str | None] = mapped_column(Text, nullable=True)
    note_updated_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    # Feed refresh: timestamp of last time article was shown but not clicked
    last_impressed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    # Manual "already seen" flag — permanent strong penalty, no time decay
    manually_impressed: Mapped[bool] = mapped_column(default=False, server_default="false")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow
    )

    # Relations
    content: Mapped["Content"] = relationship(back_populates="user_statuses")

