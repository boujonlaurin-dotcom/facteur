"""Modèle EssentielLetterRow — lettre du jour de l'Essentiel (Story 9.6).

Une ligne par (user, date, variante serein). La lettre stocke son propre
snapshot des 5 picks (`articles`) : les picks du digest bougent en journée
(pénalité is_read), la lettre reste figée ; seuls les flags is_read/is_saved
sont réhydratés au serve.
"""

import uuid
from datetime import date, datetime
from typing import Any
from uuid import UUID

from sqlalchemy import Boolean, Date, DateTime, Index, String, UniqueConstraint
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class EssentielLetterRow(Base):
    """Lettre Essentiel pré-générée (job nocturne) ou on-demand.

    Attributes:
        user_id: UUID de l'utilisateur.
        target_date: Date de la lettre.
        is_serene: Variante serein (générée on-demand, cachée).
        letter: JSONB — `EssentielLetter` sérialisée (chapo/rubriques/footer).
        articles: JSONB — snapshot des `EssentielArticle` référencés.
        model: Modèle LLM utilisé (traçabilité coût/qualité).
    """

    __tablename__ = "essentiel_letters"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "target_date",
            "is_serene",
            name="uq_essentiel_letters_user_date_serene",
        ),
        # Purge 30j + lookups par date.
        Index("ix_essentiel_letters_target_date", "target_date"),
    )

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[UUID] = mapped_column(PGUUID(as_uuid=True), nullable=False)
    target_date: Mapped[date] = mapped_column(Date, nullable=False)
    is_serene: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )
    letter: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False)
    articles: Mapped[list[dict[str, Any]]] = mapped_column(
        JSONB, nullable=False, default=list, server_default="[]"
    )
    model: Mapped[str | None] = mapped_column(String(60), nullable=True)
    generated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), default=datetime.utcnow, nullable=False
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
