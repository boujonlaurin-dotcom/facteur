"""DigestGenerationState model — per-user observability for the digest batch.

Tracks the generation lifecycle for each (user, target_date) pair so we can
answer "why is this user still on yesterday's digest?" without scanning logs.
"""

import uuid
from datetime import date, datetime
from uuid import UUID

from sqlalchemy import Date, DateTime, Index, Integer, String, Text, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class DigestGenerationState(Base):
    """Tracks digest generation attempts and outcomes per user per day.

    Statuses:
        - "pending"     : enqueued, not yet started
        - "in_progress" : worker picked up the user
        - "success"     : both variants generated successfully
        - "failed"      : last attempt failed; see last_error
        - "skipped"     : intentionally skipped (e.g. cold user)
    """

    __tablename__ = "digest_generation_state"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "target_date",
            name="uq_digest_generation_state_user_date",
        ),
        Index("ix_digest_generation_state_target_date", "target_date"),
        Index("ix_digest_generation_state_status", "status"),
    )

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), nullable=False)
    target_date: Mapped[date] = mapped_column(Date, nullable=False)
    status: Mapped[str] = mapped_column(
        String(20), nullable=False, default="pending", server_default="pending"
    )
    attempts: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default="0"
    )
    last_error: Mapped[str | None] = mapped_column(Text, nullable=True)
    started_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    finished_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow, nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=datetime.utcnow,
        onupdate=datetime.utcnow,
        nullable=False,
    )
