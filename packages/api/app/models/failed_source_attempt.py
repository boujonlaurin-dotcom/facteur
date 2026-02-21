"""Modèle pour tracker les tentatives d'ajout de source échouées."""

import uuid
from datetime import datetime
from typing import Optional
from uuid import UUID

from sqlalchemy import DateTime, Index, String, Text
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class FailedSourceAttempt(Base):
    """Tentative d'ajout de source échouée — aide à améliorer la découverte."""

    __tablename__ = "failed_source_attempts"

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), nullable=False, index=True)
    input_text: Mapped[str] = mapped_column(String(500), nullable=False)
    input_type: Mapped[str] = mapped_column(String(20), nullable=False)  # "url" or "keyword"
    endpoint: Mapped[str] = mapped_column(String(20), nullable=False)  # "detect" or "custom"
    error_message: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow, nullable=False, index=True
    )

    __table_args__ = (
        Index("ix_failed_source_attempts_input_text", "input_text"),
    )
