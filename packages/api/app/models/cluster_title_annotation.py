"""Cluster title annotation cache (Story 7.4 — diff highlighting).

One row per (cluster_id, content_id) holding the precomputed strong_tokens
used by the perspective panel to highlight divergent words across titles
covering the same story. Lazy populated on the first /perspectives tap.
"""

from datetime import datetime
from uuid import UUID

from sqlalchemy import DateTime, ForeignKey, Index, String, func
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class ClusterTitleAnnotation(Base):
    """Precomputed strong-token annotation for one article inside a cluster.

    `strong_tokens` is the list of POS-filtered tokens kept from the title
    (shape: `[{start, end, text, lemma, pos, entity_kind?}]`). The diff
    between two titles is computed at request time from these tokens.

    `semantic_equiv` stays NULL in Sprint 1 (phase déterministe). Phase 2
    LLM raffinement (Mistral-small) will populate it without touching
    existing rows — `model_version` lets us re-run a cohort behind a feature
    flag without losing history.

    No FK on `cluster_id` (denormalized — `Content.cluster_id` itself has
    no FK because there is no `clusters` table).
    """

    __tablename__ = "cluster_title_annotations"
    __table_args__ = (Index("ix_cta_cluster_id", "cluster_id"),)

    cluster_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True
    )
    content_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("contents.id", ondelete="CASCADE"),
        primary_key=True,
    )
    strong_tokens: Mapped[list] = mapped_column(JSONB, nullable=False)
    semantic_equiv: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    model_version: Mapped[str] = mapped_column(String(32), nullable=False)
    computed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
