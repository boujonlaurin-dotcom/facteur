"""Modèle pour logger toutes les recherches de sources (succès + abandon)."""

import uuid
from datetime import datetime
from uuid import UUID

from sqlalchemy import Boolean, DateTime, Index, Integer, String
from sqlalchemy.dialects.postgresql import ARRAY, JSONB
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class SourceSearchLog(Base):
    """Une ligne par appel à `/sources/smart-search` finalisé.

    Permet de re-jouer offline les recherches utilisateurs et d'identifier
    les sources manquantes du catalogue ou les requêtes qui partent en
    pipeline complet sans résultat exploitable.
    """

    __tablename__ = "source_search_logs"

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), nullable=False)
    query_raw: Mapped[str] = mapped_column(String(500), nullable=False)
    query_normalized: Mapped[str] = mapped_column(String(500), nullable=False)
    content_type: Mapped[str | None] = mapped_column(String(20), nullable=True)
    expand: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    layers_called: Mapped[list[str]] = mapped_column(
        ARRAY(String), nullable=False, default=list
    )
    result_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    top_results: Mapped[list[dict]] = mapped_column(
        JSONB, nullable=False, default=list
    )
    latency_ms: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    cache_hit: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    abandoned: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow, nullable=False
    )

    __table_args__ = (
        Index("ix_source_search_logs_created_at", "created_at"),
        Index("ix_source_search_logs_query_normalized", "query_normalized"),
        Index("ix_source_search_logs_user_id", "user_id"),
    )
