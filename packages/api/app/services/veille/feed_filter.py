"""Feed veille curé par score (refonte curation).

Pipeline : **prefilter SQL (axes forts) → scoring piliers → seuil → tri par
score**, en réutilisant le moteur de la Tournée (`PillarScoringEngine`). Le
thème macro est retiré du prédicat : un article « thème seul » ne peut donc
jamais entrer dans le pool de candidats. Les axes forts sont les topics/angles,
les sources suivies et les mots-clés (globaux + grappes d'angles).
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from uuid import UUID

import structlog
from sqlalchemy import exists, func, or_, select
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
from app.services.ml.classification_service import VALID_TOPIC_SLUGS
from app.services.recommendation.filter_presets import (
    apply_serein_filter,
    load_serein_preferences,
)
from app.services.recommendation.helpers.diversification import diversify
from app.services.recommendation.helpers.keyword_match import matches_word_boundary
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
    # Langues des sources configurées (`Source.language`), ∪ {fr}, pour filtrer
    # le Bloc B « Couverture élargie » (jamais le Bloc A). Cf. G1 refonte veille.
    source_languages: set[str] = field(default_factory=set)

    @property
    def topic_slugs(self) -> list[str]:
        # Filtre les slugs vides : un `topic_id` non canonique est neutralisé en
        # "" par `load_veille_filters` (G2) — il ne doit ni entrer dans le
        # prédicat SQL, ni compter comme axe `topic`. Sa grappe de mots-clés,
        # elle, survit via `all_keywords`.
        return [a.topic_id for a in self.angles if a.topic_id]

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

    # G2 — un `topic_id` non canonique (les 95 slugs `angle-*` morts issus des
    # suggestions LLM) est neutralisé en "" : il sort du prédicat SQL, de
    # `matched_on` et de `user_subtopics` (le floor redevient honnête). Sa grappe
    # de mots-clés survit (custom-topic `slug_parent=""` côté scoring_context).
    # La canonicité se lit sur `VALID_TOPIC_SLUGS`, pas sur les clés d'une table
    # de libellés : ce test portait sur l'ancien `SUBTOPIC_LABELS` du pilier
    # Pertinence, dérivé d'une taxonomie périmée. Il neutralisait donc des
    # `topic_id` parfaitement valides — et parmi les plus suivis (`energy`,
    # `politics`, `usa`, `justice`, `europe`, `tech`) — tout en laissant passer
    # 32 slugs fantômes.
    canon = VALID_TOPIC_SLUGS
    angles = [
        VeilleAngle(
            topic_id=topic_id if (topic_id or "").lower().strip() in canon else "",
            label=label,
            keywords=keywords_by_topic.get(row_id, []),
        )
        for row_id, topic_id, label in topic_rows
    ]

    # Jointure Source pour porter la langue des sources configurées (G1) — le
    # Bloc B filtre les langues à `source_languages ∪ {fr}`. `why` n'est plus lu
    # ici (tokenisation d'intention retirée, E) ; il reste servi par l'endpoint
    # config via son propre chemin (badge santé inchangé).
    source_rows = (
        await session.execute(
            select(VeilleSource.source_id, Source.language)
            .join(Source, Source.id == VeilleSource.source_id)
            .where(VeilleSource.veille_config_id == config.id)
        )
    ).all()
    source_ids = [sid for sid, _lang in source_rows]
    source_languages = {
        lang.lower().strip() for _sid, lang in source_rows if lang and lang.strip()
    }

    return VeilleFilters(
        theme_id=config.theme_id or None,
        angles=angles,
        source_ids=source_ids,
        global_keywords=global_keywords,
        source_languages=source_languages,
    )


def build_strong_predicate(filters: VeilleFilters):
    r"""Clause `OR` SQL sur les axes **forts uniquement** (jamais le thème).

    - `topic` : Content.topics && topic_slugs — index GIN ix_contents_topics
    - `source` : Content.source_id IN (source_ids) — index ix_contents_source_id
    - `keyword` : title ~* OR description ~* en **mot-entier** (globaux + grappes)

    Le matching mots-clés est en mot-entier (regex POSIX `\m…\M`) et non en
    sous-chaîne : sans ça des mots-clés d'angle génériques (« titre », « finale »,
    « draft »…) ramènent des articles hors-sujet (plan veille V0, Problème 3).
    Aligné sur `layers/user_custom_topics.py` (regex `\b…\b`).

    Renvoie `None` si aucun axe fort (p.ex. thème seul) → exclusion voulue.
    """
    clauses = []
    if filters.topic_slugs:
        clauses.append(Content.topics.overlap(filters.topic_slugs))
    if filters.source_ids:
        clauses.append(Content.source_id.in_(filters.source_ids))
    for kw in filters.all_keywords:
        # `\m` / `\M` = bornes de mot Postgres (équivalent SQL de `\b…\b`).
        pattern = r"\m" + re.escape(kw) + r"\M"
        clauses.append(Content.title.op("~*")(pattern))
        clauses.append(Content.description.op("~*")(pattern))
    return or_(*clauses) if clauses else None


def build_topic_keyword_predicate(filters: VeilleFilters):
    r"""Clause `OR` SQL sur les axes **topic + mots-clés uniquement** (Bloc B).

    Identique à `build_strong_predicate` mais **sans** la clause `source_id IN`.
    C'est le prédicat du Bloc B « Couverture élargie » : il ratisse le pool
    global sur les topics/mots-clés ; l'appelant le combine avec
    `source_id NOTIN config_sources` pour ne garder que les **autres** sources
    (les sources configurées vivent dans le Bloc A, fenêtre 30 j, laisser-passer).

    Renvoie `None` si aucun axe topic/mot-clé → pas de Bloc B (p.ex. config
    source-seule).
    """
    clauses = []
    if filters.topic_slugs:
        clauses.append(Content.topics.overlap(filters.topic_slugs))
    for kw in filters.all_keywords:
        pattern = r"\m" + re.escape(kw) + r"\M"
        clauses.append(Content.title.op("~*")(pattern))
        clauses.append(Content.description.op("~*")(pattern))
    return or_(*clauses) if clauses else None


def _matched_axes(
    content: Content,
    topic_slugs: set[str],
    source_ids: set[UUID],
    keywords: list[str],
) -> tuple[list[str], bool]:
    """Axes qualifiants + drapeau `floor_qualified` (floor durci, B).

    Renvoie ``(axes, floor_qualified)`` :

    - ``axes`` (exposés au front — sémantique ``matched_on`` **inchangée**) :
      ``keyword`` dès **1** hit mot-entier, ``topic``/``source`` selon
      appartenance. Le thème n'est pas un axe qualifiant (inclusion gérée par le
      prédicat fort + le seuil). Mot-entier via ``matches_word_boundary``
      (primitive du pilier Pertinence et du prédicat SQL ``\\m…\\M``) et non
      sous-chaîne : sinon un mot-clé survit sur un fragment (« nets » ⊂
      « internets »).
    - ``floor_qualified`` (**B**) : ``True`` si l'article porte un axe ``topic``
      **OU** un hit « fort » (mot-clé multi-mots, p.ex. « coupe du monde »)
      **OU** ≥ ``VEILLE_FLOOR_MIN_KEYWORD_HITS`` hits **distincts**. Un unigramme
      générique seul ne qualifie plus (fix du bruit sur les kw LLM génériques).
      Un même mot-clé en titre+description = 1 hit (``matches_word_boundary``
      couvre les deux champs).

    Collections pré-calculées par l'appelant (hot path : ~CANDIDATE_CAP appels).
    """
    axes: list[str] = []
    if topic_slugs and content.topics and any(t in topic_slugs for t in content.topics):
        axes.append("topic")
    if source_ids and content.source_id in source_ids:
        axes.append("source")

    min_hits = ScoringWeights.VEILLE_FLOOR_MIN_KEYWORD_HITS
    hits = 0
    strong = False
    if keywords:
        title_lower = (content.title or "").lower()
        desc_lower = (content.description or "").lower()
        for kw in keywords:
            if not matches_word_boundary(kw, title_lower, desc_lower):
                continue
            hits += 1
            if " " in kw:  # mot-clé multi-mots = hit « fort »
                strong = True
            if strong or hits >= min_hits:
                break  # qualifié (fort ou ≥ N) — inutile de continuer
        if hits:
            axes.append("keyword")

    floor_qualified = ("topic" in axes) or strong or hits >= min_hits
    return axes, floor_qualified


def _score_block(
    candidates: list[Content],
    context,
    filters: VeilleFilters,
    *,
    apply_floor: bool,
    apply_threshold: bool,
    diversity_cap: int | None = None,
    block: str = "?",
) -> list[tuple[Content, float, list[str]]]:
    """Score chaque candidat, trie par score, et applique floor/seuil/cap selon le bloc.

    Refonte curation deux blocs — un seul moteur de scoring (`PillarScoringEngine`),
    deux politiques de filtrage paramétrées :

    - **Bloc A « Tes sources »** (`apply_floor=True`, `apply_threshold=True`,
      `diversity_cap=N`) : **gate-all** (ajustements « released »). Les articles
      d'une source configurée (fenêtre 30 j) sont scorés + triés, puis filtrés
      par le **floor** (« la source est un boost, pas un free-pass ») et le
      **seuil**, enfin **cap de diversité** à `N`/source via `diversify()`. Le
      floor ne mord que si la config porte un axe topic/mot-clé
      (`floor_active`) : une config **purement source** garde donc le
      laisser-passer (la source est l'unique filtre voulu). Avant les
      ajustements « released », le Bloc A était en laisser-passer total
      (`apply_floor=False`) — c'est ce qui inondait une veille étroite (NBA)
      d'articles hors-sujet d'une source large (The Athletic).
    - **Bloc B « Couverture élargie »** (`apply_floor=True`,
      `apply_threshold=True`) : comportement historique (Story 23.4) —

      1. **Floor durci (B)** : « la source est un boost, pas un free-pass » — un
         candidat dont les axes ⊆ ``{source}`` est écarté ; en plus, un
         *keyword-only* ne qualifie que sur un hit fort (multi-mots) ou ≥
         ``VEILLE_FLOOR_MIN_KEYWORD_HITS`` hits distincts (cf. `_matched_axes`).
         N'agit que si un axe topic/keyword existe (``floor_active``).
      2. **Gate pertinence (A)** : au-dessus du floor, on exige aussi
         pertinence normalisée ≥ ``VEILLE_PERTINENCE_GATE`` — le seuil composite
         seul laisse passer un hors-sujet frais+propre (source+fraîcheur+qualité
         = 60 % du poids). Même condition d'activation que le floor.
      3. **Seuil composite** : on garde score ≥ ``VEILLE_RELEVANCE_THRESHOLD``.
         Plus d'anti-starvation (C) : aucun candidat sous le seuil n'est réadmis
         — un feed court honnête vaut mieux qu'un feed rempli de bruit.
    """
    engine = PillarScoringEngine()
    # Pré-calcul hors boucle : ces dérivations sont stables sur tout le fetch.
    topic_slugs = set(filters.topic_slugs)
    source_ids = set(filters.source_ids)
    keywords = filters.all_keywords
    threshold = ScoringWeights.VEILLE_RELEVANCE_THRESHOLD
    gate = ScoringWeights.VEILLE_PERTINENCE_GATE
    # Floor et gate n'ont de sens qu'avec un axe topic/keyword à côté de la
    # source. Sans cela (config source-seule), la source est l'unique filtre :
    # ni floor ni gate (passthrough conservé — fallback documenté).
    has_topic_or_kw = bool(topic_slugs or keywords)
    floor_active = apply_floor and has_topic_or_kw
    gate_active = apply_threshold and has_topic_or_kw

    passing: list[tuple[Content, float, list[str]]] = []
    max_score = 0.0
    floor_pruned_count = 0
    gate_pruned_count = 0
    threshold_pruned_count = 0
    for content in candidates:
        axes, floor_qualified = _matched_axes(
            content, topic_slugs, source_ids, keywords
        )
        if floor_active and not floor_qualified:
            # Floor durci (B) : ni topic, ni hit fort, ni ≥ N hits distincts.
            floor_pruned_count += 1
            continue
        result = engine.compute_score(content, context)
        if gate_active and result.pillar_scores.get("pertinence", 0.0) < gate:
            # Gate pertinence (A) : composite franchi mais lien au sujet trop
            # faible → écarté.
            gate_pruned_count += 1
            continue
        score = result.final_score
        if score > max_score:
            max_score = score
        if not apply_threshold or score >= threshold:
            passing.append((content, score, axes))
        else:
            # Seuil composite (C) : sous le seuil → écarté, sans réadmission.
            threshold_pruned_count += 1

    _epoch = datetime.min.replace(tzinfo=UTC)
    passing.sort(
        key=lambda t: (t[1], t[0].published_at or _epoch),
        reverse=True,
    )

    if diversity_cap is not None:
        # Cap par source — préserve l'ordre par score (déjà trié), pas de
        # fallback : on veut un plafond strict, pas une cible de taille.
        passing = diversify(
            passing,
            key_fn=lambda t: t[0].source_id,
            max_per_key=diversity_cap,
            fallback_ok=False,
        )

    logger.info(
        "veille.feed_scored",
        block=block,
        candidate_count=len(candidates),
        pass_count=len(passing),
        max_score=round(max_score, 1),
        floor_pruned_count=floor_pruned_count,
        gate_pruned_count=gate_pruned_count,
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
) -> tuple[list[tuple[Content, list[str], str]], bool]:
    """Récupère le feed veille curé pour `user_id`, en **deux blocs**.

    Returns (items_with_axes_and_group, has_more). Chaque item est un triple
    ``(Content, matched_on, group)`` où ``group`` ∈ ``{"sources", "elargie"}`` :

    - **Bloc A « Tes sources »** (``group="sources"``) : articles des sources
      configurées, fenêtre 30 j, **pool équitable par source** (window function,
      D — une source dense n'affame plus les discrètes), scoring complet,
      **gate-all** (floor durci + gate pertinence + seuil), cap de diversité
      3/source. Floor/gate n'agissent que si la config porte un axe
      topic/mot-clé ; une config purement source garde le laisser-passer.
    - **Bloc B « Couverture élargie »** (``group="elargie"``) : articles
      topic/mots-clés **hors** sources configurées, fenêtre 7 j, **filtre langue**
      (G1 — langues des sources configurées ∪ {fr}, NULL toléré), floor durci +
      gate pertinence + seuil (plus d'anti-starvation).

    Les deux blocs scorés sont concaténés (A puis B), tagués, puis paginés sur
    l'ensemble — la pagination offset/limit reste plate côté API.

    Si aucune config active OU aucun axe fort → liste vide.
    """
    config = await _get_active_config(session, user_id)
    if config is None:
        return [], False

    filters = await load_veille_filters(session, config)
    if not filters.has_strong_axis():
        return [], False

    now = datetime.now(UTC)

    exclude_user_status = exists().where(
        UserContentStatus.content_id == Content.id,
        UserContentStatus.user_id == user_id,
        or_(
            UserContentStatus.is_hidden,
            UserContentStatus.status.in_([ContentStatus.SEEN, ContentStatus.CONSUMED]),
        ),
    )

    serein_prefs = None
    if serein:
        serein_prefs = await load_serein_preferences(session, user_id)

    def _apply_common_filters(q):
        """Filtres communs (exclusions user, source active, serein) applicables
        à un select **entité `Content`** comme à une **projection `Content.id`**
        (sous-requête de rang du Bloc A). Le join Source est requis pour
        ``is_active`` et pour le filtre serein (``Source.theme``)."""
        q = (
            q.join(Content.source)
            .where(~exclude_user_status)
            .where(Source.is_active.is_(True))
        )
        if serein_prefs is not None:
            q = apply_serein_filter(
                q,
                sensitive_themes=serein_prefs.sensitive_themes,
                excluded_topics=serein_prefs.excluded_topics,
            )
        return q

    def _base_query():
        # Select entité pour le scoring (charge Content.source en une passe).
        return _apply_common_filters(
            select(Content).options(selectinload(Content.source))
        )

    context = await build_veille_scoring_context(session, config, filters, now)

    # ─── Bloc A « Tes sources » — fenêtre 30 j, pool équitable par source ─────
    block_a: list[tuple[Content, float, list[str]]] = []
    if filters.source_ids:
        cutoff_a = now - timedelta(hours=ScoringWeights.VEILLE_CONFIGURED_RECENCY_HOURS)
        # Pool équitable (D) : au lieu d'un `ORDER BY published_at LIMIT 300`
        # global (une source dense capte tout le pool et affame les discrètes),
        # on range les candidats par source (row_number) et on retient les N
        # plus récents de **chaque** source, puis on borne l'ensemble au cap
        # externe. Sous-requête sur les seuls `id` (mêmes filtres communs).
        ranked = (
            _apply_common_filters(
                select(
                    Content.id.label("id"),
                    func.row_number()
                    .over(
                        partition_by=Content.source_id,
                        order_by=Content.published_at.desc(),
                    )
                    .label("rn"),
                )
            )
            .where(Content.source_id.in_(filters.source_ids))
            .where(Content.published_at >= cutoff_a)
            .subquery()
        )
        per_source_ids = select(ranked.c.id).where(
            ranked.c.rn <= ScoringWeights.VEILLE_BLOCK_A_PER_SOURCE_CANDIDATES
        )
        query_a = (
            _base_query()
            .where(Content.id.in_(per_source_ids))
            .order_by(Content.published_at.desc())
            .limit(ScoringWeights.VEILLE_CANDIDATE_CAP)
        )
        candidates_a = (await session.execute(query_a)).scalars().all()
        if candidates_a:
            # Gate-all (ajustements « released ») : floor + seuil aussi sur les
            # sources configurées. Le floor ne mord que si la config a un axe
            # topic/mot-clé (cf. `floor_active`) ; une config purement source
            # garde le laisser-passer.
            block_a = _score_block(
                list(candidates_a),
                context,
                filters,
                apply_floor=True,
                apply_threshold=True,
                diversity_cap=ScoringWeights.VEILLE_SOURCE_DIVERSITY_CAP,
                block="sources",
            )

    # ─── Bloc B « Couverture élargie » — fenêtre 7 j, hors sources config ────
    block_b: list[tuple[Content, float, list[str]]] = []
    topic_kw_predicate = build_topic_keyword_predicate(filters)
    if topic_kw_predicate is not None:
        cutoff_b = now - timedelta(hours=ScoringWeights.VEILLE_RECENCY_HOURS)
        query_b = (
            _base_query()
            .where(topic_kw_predicate)
            .where(Content.published_at >= cutoff_b)
        )
        if filters.source_ids:
            query_b = query_b.where(Content.source_id.notin_(filters.source_ids))
        if ScoringWeights.VEILLE_BLOCK_B_LANGUAGE_FILTER:
            # Filtre langue (G1) : le Bloc B ratisse le pool global, souvent
            # multilingue. On restreint aux langues des sources configurées
            # ∪ {fr} ; `Content.language IS NULL` passe (permissif : beaucoup
            # d'articles n'ont pas de langue détectée). Le Bloc A n'est jamais
            # filtré (source choisie = langue assumée).
            allowed_languages = filters.source_languages | {"fr"}
            query_b = query_b.where(
                or_(
                    Content.language.in_(allowed_languages),
                    Content.language.is_(None),
                )
            )
        query_b = query_b.order_by(Content.published_at.desc()).limit(
            ScoringWeights.VEILLE_CANDIDATE_CAP
        )
        candidates_b = (await session.execute(query_b)).scalars().all()
        if candidates_b:
            block_b = _score_block(
                list(candidates_b),
                context,
                filters,
                apply_floor=True,
                apply_threshold=True,
                block="elargie",
            )

    # Concaténation A→B, tag du groupe, puis pagination plate sur l'ensemble.
    tagged: list[tuple[Content, list[str], str]] = [
        (content, axes, "sources") for content, _s, axes in block_a
    ] + [(content, axes, "elargie") for content, _s, axes in block_b]

    page = tagged[offset : offset + limit]
    has_more = len(tagged) > offset + limit
    return page, has_more
