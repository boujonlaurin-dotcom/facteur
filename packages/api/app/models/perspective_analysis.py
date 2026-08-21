"""Modèle cache analyses de perspectives (Mistral) — **DÉPRÉCIÉ** (Story 35.1).

Sa clé unique est `content_id`, or l'analyse des angles 6C a besoin d'un objet
partagé par N articles d'un même sujet : cf. `app.models.coverage_analysis`.
Cette table n'a jamais contenu la moindre ligne en prod (le Reader l'interroge,
rien ne l'alimente). Elle reste en place le temps d'un cycle : la retirer est un
`DROP`, donc une migration contractante, interdite en une étape sur la DB
partagée staging/prod (expand-contract, cf. CLAUDE.md).
"""

import uuid
from datetime import datetime
from uuid import UUID

from sqlalchemy import DateTime, ForeignKey, Text, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class PerspectiveAnalysis(Base):
    """Cache persistant pour les analyses Mistral de perspectives éditoriales."""

    __tablename__ = "perspective_analyses"
    __table_args__ = (
        UniqueConstraint("content_id", name="uq_perspective_analyses_content_id"),
    )

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    content_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("contents.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    analysis_text: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default="now()",
    )
