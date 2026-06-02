"""Feed veille curé par score (refonte curation).

Pipeline : **prefilter SQL (axes forts) → scoring piliers → seuil → tri par
score**, en réutilisant le moteur de la Tournée (`PillarScoringEngine`). Le
thème macro est retiré du prédicat : un article « thème seul » ne peut donc
jamais entrer dans le pool de candidats. Les axes forts sont les topics/angles,
les sources suivies et les mots-clés (globaux + grappes d'angles).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from uuid import UUID

import structlog
from sqlalchemy import exists, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.content import Content, UserContentStatus
from app.models.enums import ContentStatus
from app.models.source import Source
from app.models.veille import (
    VeilleConfig,
    VeilleKeyword,
    VeilleSource,
    VeilleStatus,
    VeilleTopic,
)
from app.services.recommendation.filter_presets import (
    apply_serein_filter,
    load_serein_preferences,
)
from app.services.recommendation.scoring_config import ScoringWeights
from app.services.recommendation.scoring_engine import PillarScoringEngine
from app.services.veille.scoring_context import build_veille_scoring_context

logger = structlog.get_logger()


@dataclass(frozen=True)
class VeilleAngle:
    """Un angle = sujet (`topic_id`) + sa grappe de mots-clés."""

    topic_id: str
    label: str
    keywords: list[str] = field(default_factory=list)


@dataclass
class VeilleFilters:
    """Filtres chargés depuis une VeilleConfig active.

    `theme_id` est un signal faible (scoring uniquement, jamais dans le
    prédicat). Les axes forts qui peuplent le pool de candidats sont
    `angles` (topics + grappes), `source_ids` et `global_keywords`.
    """

    theme_id: str | None = None
    angles: list[VeilleAngle] = field(default_factory=list)
    source_ids: list[UUID] = field(default_factory=list)
    global_keywords: list[str] = field(default_factory=list)

    @property
    def topic_slugs(self) -> list[str]:
        return [a.topic_id for a in self.angles]

    @property
    def all_keywords(self) -> list[str]:
        """Mots-clés globaux + grappes d'angles, dédupliqués (ordre stable)."""
        seen: set[str] = set()
        out: list[str] = []
        for kw in self.global_keywords:
            low = kw.lower().strip()
            if low and low not in seen:
                seen.add(low)
                out.append(low)
        for angle in self.angles:
            for kw in angle.keywords:
                low = kw.lower().strip()
                if low and low not in seen:
                    seen.add(low)
                    out.append(low)
        return out

    def has_strong_axis(self) -> bool:
        return bool(self.topic_slugs or self.source_ids or self.all_keywords)


async def _get_active_config(
    session: AsyncSession, user_id: UUID
) -> VeilleConfig | None:
    stmt = select(VeilleConfig).where(
        VeilleConfig.user_id == user_id,
        VeilleConfig.status == VeilleStatus.ACTIVE.value,
    )
    return (await session.execute(stmt)).scalars().first()


async def load_veille_filters(
    session: AsyncSession, config: VeilleConfig
) -> VeilleFilters:
    """Charge angles (topics + grappes), sources et mots-clés globaux.

    Les `VeilleKeyword` rattachés à un angle (`veille_topic_id`) forment la
    grappe de cet angle ; ceux sans rattachement (`veille_topic_id IS NULL`)
    sont des mots-clés globaux de la config.
    """
    topic_rows = (
        await session.execute(
            select(VeilleTopic.id, VeilleTopic.topic_id, VeilleTopic.label)
            .where(VeilleTopic.veille_config_id == config.id)
            .order_by(VeilleTopic.position, VeilleTopic.created_at)
        )
    ).all()

    keyword_rows = (
        await session.execute(
            select(VeilleKeyword.keyword, VeilleKeyword.veille_topic_id)
            .where(VeilleKeyword.veille_config_id == config.id)
            .order_by(VeilleKeyword.position)
        )
    ).all()

    keywords_by_topic: dict[UUID, list[str]] = {}
    global_keywords: list[str] = []
    for keyword, topic_id in keyword_rows:
        if topic_id is None:
            global_keywords.append(keyword)
        else:
            keywords_by_topic.setdefault(topic_id, []).append(keyword)

    angles = [
        VeilleAngle(
            topic_id=topic_id,
            label=label,
            keywords=keywords_by_topic.get(row_id, []),
        )
        for row_id, topic_id, label in topic_rows
    ]

    sources = (
        (
            await session.execute(
                select(VeilleSource.source_id).where(
                    VeilleSource.veille_config_id == config.id
                )
            )
        )
        .scalars()
        .all()
    )

    return VeilleFilters(
        theme_id=config.theme_id or None,
        angles=angles,
        source_ids=list(sources),
        global_keywords=global_keywords,
    )


def build_strong_predicate(filters: VeilleFilters):
    """Clause `OR` SQL sur les axes **forts uniquement** (jamais le thème).

    - `topic` : Content.topics && topic_slugs — index GIN ix_contents_topics
    - `source` : Content.source_id IN (source_ids) — index ix_contents_source_id
    - `keyword` : title ILIKE OR description ILIKE (globaux + grappes d'angles)

    Renvoie `None` si aucun axe fort (p.ex. thème seul) → exclusion voulue.
    """
    clauses = []
    if filters.topic_slugs:
        clauses.append(Content.topics.overlap(filters.topic_slugs))
    if filters.source_ids:
        clauses.append(Content.source_id.in_(filters.source_ids))
    for kw in filters.all_keywords:
        pattern = f"%{kw}%"
        clauses.append(Content.title.ilike(pattern))
        clauses.append(Content.description.ilike(pattern))
    return or_(*clauses) if clauses else None


def _matched_axes(
    content: Content,
    topic_slugs: set[str],
    source_ids: set[UUID],
    keywords: list[str],
) -> list[str]:
    """Axes **qualifiants** sur lesquels l'article matche (exposés au front).

    Le thème n'est plus un axe qualifiant : l'inclusion est gérée par le
    prédicat fort + le seuil de score. On garde topic/source/keyword. Les
    collections sont pré-calculées par l'appelant (hot path : ~CANDIDATE_CAP
    appels par fetch).
    """
    axes: list[str] = []
    if topic_slugs and content.topics:
        if any(t in topic_slugs for t in content.topics):
            axes.append("topic")
    if source_ids and content.source_id in source_ids:
        axes.append("source")
    if keywords:
        title_lower = (content.title or "").lower()
        desc_lower = (content.description or "").lower()
        if any(kw in title_lower or kw in desc_lower for kw in keywords):
            axes.append("keyword")
    return axes


def _score_and_rank(
    candidates: list[Content],
    context,
    filters: VeilleFilters,
) -> list[tuple[Content, float, list[str]]]:
    """Score chaque candidat, applique le floor + le seuil, trie par score.

    Pipeline (Story 23.4) :

    1. **Floor** — « la source est un boost, pas un free-pass » : tout candidat
       dont les axes qualifiants ⊆ ``{source}`` (ni topic ni mot-clé) est écarté
       *avant* le seuil. Plus chirurgical qu'un narrow-predicate : on préserve
       l'UX ``matched_on`` et les articles on-topic venant d'une source suivie.
       Le floor **ne s'active que si la config définit un axe topic/keyword** à
       gater : une config *source-seule* (aucun topic, aucun mot-clé) garde son
       comportement historique — ses sources **sont** le filtre, leurs articles
       passent.
    2. **Seuil** — parmi les candidats on-axis, on garde ceux dont le score
       final ≥ ``VEILLE_RELEVANCE_THRESHOLD``.
    3. **Anti-starvation** — si moins de ``VEILLE_MIN_FEED_SIZE`` passent ET que
       des candidats on-axis ont été coupés par le *seuil* (jamais par le floor),
       on relâche le seuil d'un cran (``max(threshold-8, 40)``) et on réadmet
       ceux qui repassent — sans jamais réadmettre un article floor-pruned.
    """
    engine = PillarScoringEngine()
    # Pré-calcul hors boucle : ces dérivations sont stables sur tout le fetch.
    topic_slugs = set(filters.topic_slugs)
    source_ids = set(filters.source_ids)
    keywords = filters.all_keywords
    threshold = ScoringWeights.VEILLE_RELEVANCE_THRESHOLD
    # Le floor n'a de sens que s'il existe un axe topic/keyword à côté de la
    # source. Sans cela (config source-seule), la source est l'unique filtre.
    floor_active = bool(topic_slugs or keywords)

    passing: list[tuple[Content, float, list[str]]] = []
    # Candidats on-axis sous le seuil — réservés à l'anti-starvation.
    below_threshold: list[tuple[Content, float, list[str]]] = []
    max_score = 0.0
    floor_pruned_count = 0
    for content in candidates:
        axes = _matched_axes(content, topic_slugs, source_ids, keywords)
        if floor_active and "topic" not in axes and "keyword" not in axes:
            # Floor : axes ⊆ {source} (ou vide) → source-seul, écarté.
            floor_pruned_count += 1
            continue
        result = engine.compute_score(content, context)
        score = result.final_score
        if score > max_score:
            max_score = score
        if score >= threshold:
            passing.append((content, score, axes))
        else:
            below_threshold.append((content, score, axes))

    threshold_pruned_count = len(below_threshold)
    if len(passing) < ScoringWeights.VEILLE_MIN_FEED_SIZE and below_threshold:
        relaxed = max(threshold - 8.0, 40.0)
        if relaxed < threshold:
            readmitted = [item for item in below_threshold if item[1] >= relaxed]
            passing.extend(readmitted)
            threshold_pruned_count -= len(readmitted)

    _epoch = datetime.min.replace(tzinfo=UTC)
    passing.sort(
        key=lambda t: (t[1], t[0].published_at or _epoch),
        reverse=True,
    )
    logger.info(
        "veille.feed_scored",
        candidate_count=len(candidates),
        pass_count=len(passing),
        max_score=round(max_score, 1),
        floor_pruned_count=floor_pruned_count,
        threshold_pruned_count=threshold_pruned_count,
    )
    return passing


async def fetch_veille_feed(
    session: AsyncSession,
    user_id: UUID,
    *,
    limit: int = 20,
    offset: int = 0,
    serein: bool = False,
) -> tuple[list[tuple[Content, list[str]]], bool]:
    """Récupère le feed veille curé pour `user_id`.

    Returns (items_with_axes, has_more). Pipeline : prefilter SQL sur axes
    forts (≤ CANDIDATE_CAP) → scoring piliers → seuil → tri par score, puis
    pagination sur l'ensemble scoré. Contrat API (limit/offset/has_more)
    inchangé.

    Si aucune config active OU aucun axe fort (thème seul) → liste vide.
    """
    config = await _get_active_config(session, user_id)
    if config is None:
        return [], False

    filters = await load_veille_filters(session, config)
    predicate = build_strong_predicate(filters)
    if predicate is None:
        return [], False

    now = datetime.now(UTC)
    cutoff = now - timedelta(hours=ScoringWeights.VEILLE_RECENCY_HOURS)

    exclude_user_status = exists().where(
        UserContentStatus.content_id == Content.id,
        UserContentStatus.user_id == user_id,
        or_(
            UserContentStatus.is_hidden,
            UserContentStatus.status.in_([ContentStatus.SEEN, ContentStatus.CONSUMED]),
        ),
    )

    query = (
        select(Content)
        .join(Content.source)
        .options(selectinload(Content.source))
        .where(~exclude_user_status)
        .where(predicate)
        .where(Source.is_active.is_(True))
        .where(Content.published_at >= cutoff)
    )

    if serein:
        serein_prefs = await load_serein_preferences(session, user_id)
        query = apply_serein_filter(
            query,
            sensitive_themes=serein_prefs.sensitive_themes,
            excluded_topics=serein_prefs.excluded_topics,
        )

    query = query.order_by(Content.published_at.desc()).limit(
        ScoringWeights.VEILLE_CANDIDATE_CAP
    )

    candidates = (await session.execute(query)).scalars().all()
    if not candidates:
        return [], False

    context = await build_veille_scoring_context(session, config, filters, now)
    scored = _score_and_rank(list(candidates), context, filters)

    page = scored[offset : offset + limit]
    has_more = len(scored) > offset + limit
    return [(content, axes) for content, _score, axes in page], has_more
