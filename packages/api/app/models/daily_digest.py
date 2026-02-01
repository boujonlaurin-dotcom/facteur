"""Modèle DailyDigest pour le digest quotidien (Epic 10)."""

import uuid
from datetime import date, datetime
from typing import TYPE_CHECKING, Any, Optional
from uuid import UUID

from sqlalchemy import Date, DateTime, ForeignKey, Index, UniqueConstraint
from sqlalchemy.dialects.postgresql import JSONB, UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base

if TYPE_CHECKING:
    pass  # No direct relationships - items stored as JSONB


class DailyDigest(Base):
    """Digest quotidien de 5 articles pour un utilisateur.
    
    Remplace le modèle DailyTop3 (3 articles) par un digest plus riche
    avec 5 articles sélectionnés pour créer un sentiment de "mission accomplie".
    
    Les articles sont stockés dans une colonne JSONB 'items' qui contient
    un tableau de 5 objets avec les références content_id et les métadonnées.
    
    Attributes:
        user_id: UUID de l'utilisateur.
        target_date: Date du digest (généralement aujourd'hui).
        items: JSONB array de 5 articles [{"content_id": "...", "rank": 1, 
               "reason": "...", "source_slug": "..."}, ...]
        generated_at: Date/heure de génération du digest.
    """

    __tablename__ = "daily_digest"
    __table_args__ = (
        # Un seul digest par (user, date)
        UniqueConstraint("user_id", "target_date", name="uq_daily_digest_user_date"),
        Index("ix_daily_digest_user_id", "user_id"),
        Index("ix_daily_digest_target_date", "target_date"),
        Index("ix_daily_digest_generated_at", "generated_at"),
    )

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), nullable=False, index=True
    )
    target_date: Mapped[date] = mapped_column(
        Date, nullable=False
    )
    items: Mapped[list[dict[str, Any]]] = mapped_column(
        JSONB, nullable=False, default=list, server_default="[]"
    )
    generated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow, nullable=False
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow, nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
    )

    # Pas de relations directes - les content_ids sont dans items JSONB
    # Les articles sont récupérés via des requêtes séparées si nécessaire
