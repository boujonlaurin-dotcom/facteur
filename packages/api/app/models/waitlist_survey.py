"""Modèle survey post-signup waitlist."""

from datetime import UTC, datetime
from uuid import UUID, uuid4

from sqlalchemy import DateTime, ForeignKey, String, Text
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class WaitlistSurveyResponse(Base):
    """Réponses au micro-survey post-inscription waitlist."""

    __tablename__ = "waitlist_survey_responses"

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid4
    )
    waitlist_entry_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("waitlist_entries.id", ondelete="CASCADE"),
        nullable=False,
    )
    info_source: Mapped[str] = mapped_column(String(100), nullable=False)
    main_pain: Mapped[str] = mapped_column(Text, nullable=False)
    willingness: Mapped[str] = mapped_column(String(100), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(UTC),
    )
