"""Analyse des angles (6C) — une analyse par **sujet**, liée à N articles.

Remplace le couple « analyse dupliquée dans le JSONB du digest (par user) » /
`perspective_analyses` (par `content_id`, jamais alimentée). Le Reader résout
``content_id → analyse`` par jointure sur `coverage_analysis_articles`, donc le
même sujet sert tous les points d'entrée (digest, Flux Continu, Veille, Tournée,
widget) : ce sont les mêmes lignes `contents`.

Story 35.1 (plan « Reader Analyse des angles 6C », PR 1).
"""

import uuid
from datetime import datetime
from uuid import UUID

from sqlalchemy import (
    DateTime,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
    text,
)
from sqlalchemy.dialects.postgresql import ARRAY, JSONB
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base

# Valeurs de `state` — miroir Python du CHECK de la migration ca01.
CONSENSUS_STATE_AVAILABLE = "available"
CONSENSUS_STATE_PENDING = "pending"
CONSENSUS_STATE_UNAVAILABLE = "unavailable"


class CoverageAnalysis(Base):
    """Analyse structurée des angles pour un sujet d'actualité.

    ``consensus`` porte le contrat lu par le Reader (accords / désaccords /
    variantes CTA) ; il est produit par un post-traitement **déterministe** de la
    sortie LLM, jamais écrit tel quel (cf. `normalize_consensus`).
    """

    __tablename__ = "coverage_analyses"
    __table_args__ = (
        UniqueConstraint("subject_key", name="uq_coverage_analyses_subject_key"),
    )

    id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    # Empreinte déterministe du jeu d'articles du sujet : rend l'écriture
    # idempotente sur un re-run du pipeline le même jour.
    subject_key: Mapped[str] = mapped_column(String(40), nullable=False)
    consensus: Mapped[dict] = mapped_column(JSONB, nullable=False)
    # "polarized" | "varied" | "convergent" | None (state != available)
    qualifier: Mapped[str | None] = mapped_column(String(16), nullable=True)
    state: Mapped[str] = mapped_column(
        String(16), nullable=False, server_default=CONSENSUS_STATE_AVAILABLE
    )
    model_version: Mapped[str | None] = mapped_column(String(64), nullable=True)
    # Domaines du corpus au moment de la génération : c'est contre eux que
    # `support_count` a été calculé, donc la référence d'attribution.
    corpus_domains: Mapped[list[str]] = mapped_column(
        ARRAY(Text), nullable=False, server_default=text("'{}'::text[]")
    )
    coverage_count: Mapped[int] = mapped_column(
        Integer, nullable=False, server_default="0"
    )
    generated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=text("now()")
    )


class CoverageAnalysisArticle(Base):
    """Lien ``sujet ↔ article``. PK composite, pas d'id de surface."""

    __tablename__ = "coverage_analysis_articles"

    coverage_analysis_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("coverage_analyses.id", ondelete="CASCADE"),
        primary_key=True,
    )
    content_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("contents.id", ondelete="CASCADE"),
        primary_key=True,
        index=True,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=text("now()")
    )
