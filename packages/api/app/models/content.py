"""Modèles contenus."""

import uuid
from datetime import datetime
from typing import TYPE_CHECKING, Optional
from uuid import UUID

from sqlalchemy import DateTime, Enum, ForeignKey, Index, Integer, String, Text, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base
from app.models.enums import ContentStatus, ContentType

if TYPE_CHECKING:
    from app.models.source import Source


class Content(Base):
    """Contenu individuel (article, épisode podcast, vidéo)."""

    __tablename__ = "contents"
    __table_args__ = (
        Index("ix_contents_guid", "guid"),
        Index("ix_contents_published_at", "published_at"),
        Index("ix_contents_source_id", "source_id"),
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
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow
    )

    # Relations
    source: Mapped["Source"] = relationship(back_populates="contents")
    user_statuses: Mapped[list["UserContentStatus"]] = relationship(
        back_populates="content", cascade="all, delete-orphan"
    )


class UserContentStatus(Base):
    """Statut d'un contenu pour un utilisateur."""

    __tablename__ = "user_content_status"
    __table_args__ = (
        UniqueConstraint("user_id", "content_id", name="uq_user_content_status_user_content"),
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
    is_hidden: Mapped[bool] = mapped_column(default=False, server_default="false")
    hidden_reason: Mapped[Optional[str]] = mapped_column(String, nullable=True)
    seen_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    time_spent_seconds: Mapped[int] = mapped_column(Integer, default=0)
    saved_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow
    )

    # Relations
    content: Mapped["Content"] = relationship(back_populates="user_statuses")

