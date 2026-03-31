"""Modèle pour le feedback utilisateur par article (pouces haut/bas + raisons)."""

import uuid
from datetime import date, datetime

from sqlalchemy import Date, DateTime, ForeignKey, String, Text, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import ARRAY
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class ArticleFeedback(Base):
    """Feedback utilisateur sur un article du digest (thumbs up/down + raisons)."""

    __tablename__ = "article_feedback"
    __table_args__ = (
        UniqueConstraint(
            "user_id", "content_id", name="uq_article_feedback_user_content"
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[uuid.UUID] = mapped_column(PGUUID(as_uuid=True), nullable=False)
    content_id: Mapped[uuid.UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("contents.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    sentiment: Mapped[str] = mapped_column(String(10), nullable=False)
    reasons: Mapped[list[str] | None] = mapped_column(ARRAY(Text), nullable=True)
    comment: Mapped[str | None] = mapped_column(Text, nullable=True)
    digest_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
