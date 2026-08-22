"""Modèle des décisions de tri de la carte « Ton Essentiel » (Story 33.1).

Une row par `(user_id, content_id, digest_date)` : l'utilisateur trie le slate
du jour article par article (`keep` / `later` / `pass`) et chaque décision est
enregistrée avec **son rang dans le slate figé** et **la taille du slate**.

Pourquoi une table neuve plutôt que `article_feedback` :

- `article_feedback` est unique sur `(user_id, content_id)` **sans la date** — on
  perdrait le re-tri d'un article d'un jour à l'autre ;
- elle ne porte ni rang ni taille de slate, or c'est exactement le dénominateur
  qui manque à la jauge de ranking (`maintenance-feed-ranking-gauge.md` : le
  dénominateur actuel est assis sur `last_impressed_at`, « ni impression ni
  position ») ;
- sa route applique déjà un ±0.15 sur les poids, ce que la décision PO n°2 de la
  story interdit explicitement.

**Collecte seule.** Écrire ici ne touche aucun poids de reco. En particulier, le
`pass` n'est **jamais** branché sur `not_interested` : cette action ajoute la
source entière à `UserPersonalization.muted_sources` sans expiration
(`digest_service.py:_trigger_personalization_mute`), ce qui ferait taire un média
parce qu'un seul papier n'a pas plu.

**Lecture** (Volet B carrousels) : `carousel_catalog.fetch_triaged_ids` relit ces
décisions comme **mémoire d'exclusion** des carrousels de découverte — un article
trié ne doit pas être re-proposé chaque jour. C'est une exclusion, pas un poids
de reco : l'invariant « Collecte seule » reste vrai côté écriture.
"""

import uuid
from datetime import date, datetime

from sqlalchemy import (
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    SmallInteger,
    String,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base


class EssentielTriageDecision(Base):
    """Une décision de tri sur un article du slate Essentiel du jour."""

    __tablename__ = "essentiel_triage_decisions"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "content_id",
            "digest_date",
            name="uq_essentiel_triage_user_content_date",
        ),
        # Vocabulaire aligné sur `TriageDecisionKind` / `TriageViaKind`
        # (app/schemas/essentiel.py, la source de vérité) et sur `TriageDecision`
        # côté mobile.
        CheckConstraint(
            "decision IN ('keep', 'later', 'pass')",
            name="ck_essentiel_triage_decision",
        ),
        CheckConstraint(
            "decided_via IN ('swipe', 'button', 'read')",
            name="ck_essentiel_triage_decided_via",
        ),
        # Dénominateur de la jauge : « toutes les décisions d'un user sur un jour ».
        Index("ix_essentiel_triage_user_date", "user_id", "digest_date"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        PGUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[uuid.UUID] = mapped_column(PGUUID(as_uuid=True), nullable=False)
    content_id: Mapped[uuid.UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("contents.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    # Clé de jour côté mobile (`TourneeProgressService.dayKey()`, bascule 07h30
    # Paris) — pas `created_at::date`, qui rangerait un tri de 7h du matin la
    # veille du slate qu'il concerne.
    digest_date: Mapped[date] = mapped_column(Date, nullable=False)
    decision: Mapped[str] = mapped_column(String(12), nullable=False)
    # Rang **dans le slate figé** au premier geste du jour, pas dans le re-rank
    # courant de `GET /api/essentiel` (qui re-classe à chaque requête).
    rank: Mapped[int | None] = mapped_column(SmallInteger, nullable=True)
    # Indispensable au dénominateur : sans lui, « rang 4 » n'a pas le même sens
    # dans un slate de 5 et dans un slate de 3 (plancher `ESSENTIEL_MIN_ARTICLES`).
    slate_size: Mapped[int | None] = mapped_column(SmallInteger, nullable=True)
    decided_via: Mapped[str | None] = mapped_column(String(8), nullable=True)
    # Temps de décision — sépare le tri réfléchi du tri distrait fait en scrollant
    # (le risque « solennité perdue » de la story, mesurable dès la V0).
    latency_ms: Mapped[int | None] = mapped_column(Integer, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )
