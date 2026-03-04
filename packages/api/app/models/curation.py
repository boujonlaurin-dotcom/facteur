"""Modèle curation_annotations pour le backoffice."""

import uuid
from datetime import date, datetime

from sqlalchemy import (
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Index,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class CurationAnnotation(Base):
    """Annotation de curation pour mesurer la qualité de l'algo."""

    __tablename__ = "curation_annotations"
    __table_args__ = (
        UniqueConstraint(
            "user_id", "content_id", "feed_date", name="uq_curation_user_content_date"
        ),
        CheckConstraint(
            "label IN ('good', 'bad', 'missing')", name="ck_curation_label"
        ),
        Index("ix_curation_annotations_user_id", "user_id"),
        Index("ix_curation_annotations_feed_date", "feed_date"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[uuid.UUID] = mapped_column(PGUUID(as_uuid=True), nullable=False)
    content_id: Mapped[uuid.UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("contents.id", ondelete="CASCADE"),
        nullable=False,
    )
    feed_date: Mapped[date] = mapped_column(Date, nullable=False)
    label: Mapped[str] = mapped_column(String(10), nullable=False)
    note: Mapped[str | None] = mapped_column(Text, nullable=True)
    annotated_by: Mapped[str] = mapped_column(
        String(50), server_default="admin", nullable=False
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
