"""EditorialHighlightsHistory — remembers recent pépite / coup de cœur picks.

Used by the editorial writer to avoid serving the same article as pépite or
coup de cœur on consecutive days, so users see fresh featured content each
morning instead of the same "top saved by community" stuck for weeks.
"""

import uuid
from datetime import date, datetime
from uuid import UUID

from sqlalchemy import Date, DateTime, Index, String
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class EditorialHighlightsHistory(Base):
    """One row per (kind, content_id, target_date) highlight pick.

    kind: "pepite" | "coup_de_coeur"
    content_id: the featured article
    target_date: the digest date the article was featured on
    """

    __tablename__ = "editorial_highlights_history"
    __table_args__ = (
        Index("ix_editorial_highlights_history_kind_date", "kind", "target_date"),
        Index("ix_editorial_highlights_history_content_id", "content_id"),
    )

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    kind: Mapped[str] = mapped_column(String(20), nullable=False)
    content_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), nullable=False)
    target_date: Mapped[date] = mapped_column(Date, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow, nullable=False
    )
