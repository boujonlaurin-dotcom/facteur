"""Modèle append-only des appels API externes (Mistral toutes passes + Brave).

Une ligne par appel API externe, miroir de `source_search_log.py`. Pas de
contrainte d'unicité → aucune contention de hot-row (vs un compteur agrégé),
et granularité temporelle par appel gratuite (analyse de pics, distribution
horaire pour le scaling WP-C/D).

Enabler observabilité scaling (WP-E) — cf.
docs/maintenance/maintenance-observabilite-scaling.md
"""

import uuid
from datetime import datetime
from uuid import UUID

from sqlalchemy import DateTime, Index, Integer, String
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class ApiUsageEvent(Base):
    """Une ligne par appel API externe (Mistral / Brave).

    `user_id` null = appel système (classification / éditorial / digest).
    `model` null = provider sans notion de modèle (Brave).
    `status` ∈ {ok, error, rate_limited}.
    """

    __tablename__ = "api_usage_events"

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    provider: Mapped[str] = mapped_column(String(16), nullable=False)
    model: Mapped[str | None] = mapped_column(String(48), nullable=True)
    call_site: Mapped[str] = mapped_column(String(48), nullable=False)
    user_id: Mapped[UUID | None] = mapped_column(PGUUID(as_uuid=True), nullable=True)
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="ok")
    latency_ms: Mapped[int | None] = mapped_column(Integer, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow, nullable=False
    )

    __table_args__ = (
        Index("ix_api_usage_events_created_at", "created_at"),
        Index("ix_api_usage_events_provider_created", "provider", "created_at"),
    )
