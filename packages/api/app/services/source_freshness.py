"""Fraîcheur des sources — garde-fou des recommandations POUSSÉES.

Une source curée / pépite qui n'a plus publié depuis longtemps (feed cassé,
jamais ingéré, ou média en sommeil) ne doit pas remonter en tête des
recommandations d'onboarding. Ce module lit la date du **dernier article** de
chaque source et la classe selon une règle **cadence-aware** — car un flux RSS
d'actualité et une chaîne YouTube n'ont pas le même rythme naturel.

Règle (knobs PO centralisés ici) :
- `type = article` (RSS/news, cadence rapide) : rien publié depuis
  `FRESH_WINDOW_DAYS` ⇒ **exclue** des surfaces poussées (feed considéré mort).
- `type ∈ {podcast, youtube, reddit}` (cadence lente) : exclue seulement si rien
  publié depuis `SLOW_WINDOW_DAYS` (réellement morte) ; sinon **conservée mais
  déclassée** (triée après les sources fraîches) tant qu'elle n'a rien publié
  sur `FRESH_WINDOW_DAYS`.

Perf : on ne **compte pas** les articles (une source active en a des milliers) —
on lit seulement la date du dernier article via un sous-select **corrélé**
`ORDER BY published_at DESC LIMIT 1` par source. L'index
`ix_contents_source_published` (source_id, published_at) résout ça en un backward
index-scan (≈1 ligne/source), soit ~30 ms pour 40 sources. On évite volontairement
le pattern `func.max(published_at) GROUP BY source_id` (utilisé ailleurs, ex.
`veille.py`, `source_service._load_articles_30d`) : mesuré à ~2,8 s ici car il
scanne **toutes** les entrées d'index des sources actives avant d'agréger, alors
que la corrélée s'arrête au premier tuple. Matérialiser `last_article_at` sur
`sources` via un job reste un follow-up possible.
"""

from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.content import Content
from app.models.enums import SourceType
from app.models.source import Source

# Fenêtre « fraîche » — un flux d'actualité doit avoir publié dans ce délai.
FRESH_WINDOW_DAYS = 30
# Fenêtre « en vie » pour les cadences lentes (podcast / vidéo) — au-delà de ce
# silence, même une source lente est considérée morte.
SLOW_WINDOW_DAYS = 90

# Types à cadence lente : un silence de 30 j n'y signifie pas un feed cassé.
SLOW_CADENCE_TYPES: frozenset[SourceType] = frozenset(
    {SourceType.PODCAST, SourceType.YOUTUBE, SourceType.REDDIT}
)


@dataclass(frozen=True)
class FreshnessVerdict:
    """Verdict de fraîcheur appliqué à une source poussée."""

    excluded: bool  # à retirer des surfaces poussées (feed mort)
    downgraded: bool  # à conserver mais reléguer en fin de liste


def _now() -> datetime:
    return datetime.now(UTC)


def _as_utc(dt: datetime) -> datetime:
    return dt if dt.tzinfo is not None else dt.replace(tzinfo=UTC)


def _source_type(source: Source) -> SourceType:
    raw = source.type
    if isinstance(raw, SourceType):
        return raw
    try:
        return SourceType(raw)
    except (ValueError, TypeError):
        # Défaut prudent : traité comme un flux rapide (règle la plus stricte).
        return SourceType.ARTICLE


def classify(source: Source, last_published_at: datetime | None) -> FreshnessVerdict:
    """Classe une source d'après la date de son dernier article.

    `last_published_at=None` signifie « aucun article » (feed jamais ingéré ou
    vidé) — traité comme le silence le plus total.
    """
    now = _now()
    fresh = last_published_at is not None and _as_utc(
        last_published_at
    ) > now - timedelta(days=FRESH_WINDOW_DAYS)
    if fresh:
        return FreshnessVerdict(excluded=False, downgraded=False)

    alive = last_published_at is not None and _as_utc(
        last_published_at
    ) > now - timedelta(days=SLOW_WINDOW_DAYS)
    if _source_type(source) in SLOW_CADENCE_TYPES:
        # Cadence lente : morte seulement si silence total sur la fenêtre large.
        if alive:
            return FreshnessVerdict(excluded=False, downgraded=True)
        return FreshnessVerdict(excluded=True, downgraded=False)

    # Flux rapide sans article récent : feed considéré mort.
    return FreshnessVerdict(excluded=True, downgraded=False)


async def fetch_last_published(
    db: AsyncSession, source_ids: list[UUID]
) -> dict[UUID, datetime]:
    """Date du dernier article par source, pour un lot d'IDs.

    Une seule requête : un sous-select corrélé `ORDER BY published_at DESC
    LIMIT 1` par source (backward index-scan sur `ix_contents_source_published`).
    Les sources sans article ne figurent pas dans le dict retourné (⇒ traitées
    comme silence total par [classify]).
    """
    if not source_ids:
        return {}

    last_pub = (
        select(Content.published_at)
        .where(Content.source_id == Source.id)
        .order_by(Content.published_at.desc())
        .limit(1)
        .correlate(Source)
        .scalar_subquery()
    )
    stmt = select(Source.id, last_pub.label("last_pub")).where(
        Source.id.in_(source_ids)
    )
    result = await db.execute(stmt)
    return {row[0]: row[1] for row in result.all() if row[1] is not None}


async def freshness_verdicts(
    db: AsyncSession, sources: list[Source]
) -> dict[UUID, FreshnessVerdict]:
    """Verdict de fraîcheur par source, en un seul aller-retour DB.

    Compose `fetch_last_published` (dernier article) + `classify` (règle
    cadence-aware) pour tout un lot. Seam unique des surfaces poussées : chaque
    appelant applique ensuite sa propre politique (exclure, déclasser, trier).
    """
    last_pub = await fetch_last_published(db, [s.id for s in sources])
    return {s.id: classify(s, last_pub.get(s.id)) for s in sources}
