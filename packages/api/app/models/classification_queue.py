"""Modèle pour la file de classification."""

import uuid
from datetime import datetime
from typing import TYPE_CHECKING
from uuid import UUID

from sqlalchemy import DateTime, ForeignKey, Index, Integer, String, Text, text
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base

if TYPE_CHECKING:
    from app.models.content import Content


class ClassificationQueue(Base):
    """File d'attente pour la classification ML des contenus."""

    __tablename__ = "classification_queue"
    __table_args__ = (
        Index("idx_queue_status_created", "status", "created_at"),
        Index("idx_queue_priority", text("priority DESC"), "created_at"),
    )

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    content_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("contents.id", ondelete="CASCADE"),
        unique=True,
        nullable=False,
    )
    status: Mapped[str] = mapped_column(
        String(20), nullable=False, default="pending"
    )  # pending, processing, completed, failed
    priority: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    retry_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    error_message: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow
    )
    processed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    # Relations
    content: Mapped["Content"] = relationship(back_populates="classification_queue")
