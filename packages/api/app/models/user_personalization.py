"""Modèle de personnalisation utilisateur."""

import uuid
from datetime import datetime
from typing import Optional
from uuid import UUID

from sqlalchemy import Boolean, DateTime, ForeignKey
from sqlalchemy.dialects.postgresql import ARRAY, UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy import Text

from app.database import Base


class UserPersonalization(Base):
    """Préférences de personnalisation d'un utilisateur (sources/thèmes mutés)."""

    __tablename__ = "user_personalization"

    user_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), 
        ForeignKey("user_profiles.user_id", ondelete="CASCADE"),
        primary_key=True
    )
    
    # Sources mutées (UUIDs des sources)
    muted_sources: Mapped[list[UUID]] = mapped_column(
        ARRAY(PGUUID(as_uuid=True)), 
        default=list,
        server_default="{}"
    )
    
    # Thèmes macro mutés (slugs comme "tech", "politics")
    muted_themes: Mapped[list[str]] = mapped_column(
        ARRAY(Text), 
        default=list,
        server_default="{}"
    )
    
    # Topics granulaires mutés (slugs comme "ai", "crypto")
    muted_topics: Mapped[list[str]] = mapped_column(
        ARRAY(Text),
        default=list,
        server_default="{}"
    )

    # Types de contenu mutés (slugs comme "article", "podcast", "youtube")
    muted_content_types: Mapped[list[str]] = mapped_column(
        ARRAY(Text),
        default=list,
        server_default="{}"
    )

    # Paywall filter: hide paid articles by default
    hide_paid_content: Mapped[bool] = mapped_column(
        Boolean, default=True, server_default="true"
    )

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow
    )
