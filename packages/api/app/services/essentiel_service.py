"""Service `essentiel` — top 5 articles transversaux du jour.

Strictement read-only : consomme la `DigestResponse` déjà calculée par la cron
nocturne via `read_digest_or_fallback`, et la projette en 5 articles cross-topic
pour la carte hi-fi "L'Essentiel du jour" du feed mobile.

Architecture :
- Le `PillarScoringEngine` (services/recommendation/scoring_engine.py) et le
  `digest_selector` ont déjà scoré + sélectionné les meilleurs articles par
  topic en amont. On *réutilise* leurs signaux (`topic.is_trending`,
  `topic.is_une`, `article.badge == "actu"`, `article.is_followed_source`)
  plutôt que de re-scorer from scratch.
- Les boosts d'Actu du jour s'alignent sur ceux du `Top3Selector` du briefing
  pour cohérence cross-feature (`BOOST_UNE=30`, `BOOST_TRENDING=40`).

Pipeline :
1. Charge le contexte user (sources/topics suivis + multiplicateurs/poids).
2. Score chaque article :
   - bonus Actu (trending/une/badge actu) — aligné top3_selector,
   - bonus source suivie (×priority_multiplier),
   - bonus topic suivi (×weight),
   - bonus perspective_count,
   - pénalité forte si `is_read` (l'écarte sauf si rien d'autre),
   - tie-break par rank.
3. **Slot lead Actu** : si un article est Actu du jour, il occupe le rank=1.
4. **Diversité dure** : max 2 articles d'une même source dans les 5.
5. Round "diversité" (1/topic) + round "remplissage", déduplication content_id.

Fallback sans préférences : le scorer dégénère en `actu_boost + perspective − rank`.
"""

import logging
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from uuid import UUID

from sqlalchemy import exists, or_, select, text
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.content import Content, UserContentStatus
from app.models.enums import ContentStatus, ContentType, InterestState, SourceType
from app.models.source import Source
from app.schemas.content import SourceMini
from app.schemas.digest import DigestResponse, DigestTopic, DigestTopicArticle
from app.schemas.essentiel import EssentielArticle, EssentielKind, EssentielResponse
from app.services.language_user_filter import (
    is_foreign_source,
)
from app.services.recommendation.filter_presets import (
    LOW_PRIORITY_SPORT_KEYWORDS,
    LOW_PRIORITY_SPORT_THEMES,
    is_news_bulletin_title,
)
from app.services.recommendation.helpers import compute_coverage_score
from app.services.recommendation.scoring_config import ScoringWeights
from app.services.text_similarity import jaccard_similarity, normalize_title

logger = logging.getLogger(__name__)

ESSENTIEL_MAX_ARTICLES = 5
ESSENTIEL_MAX_PER_SOURCE = 2  # Diversité dure : max 2 articles d'une même source.

# Plancher de qualité : en-dessous de ce nombre d'articles issus du digest, on
# complète depuis les sources suivies/favorites de l'utilisateur ; si le total
# reste < ESSENTIEL_MIN_ARTICLES, le router renvoie 202 ``preparing`` plutôt
# qu'une carte pauvre (1-2 articles).
ESSENTIEL_MIN_ARTICLES = 3
# Taille du pool de candidats frais piochés dans les sources suivies pour la
# complétion — borne le SELECT, on ne garde au plus que les slots manquants.
ESSENTIEL_SUPPLEMENT_CANDIDATE_CAP = 30

# Fenêtre de fraîcheur commune aux deux tiers de sélection. Les sources
# suivies sont prioritaires, puis le pool éditorial global frais complète.
ESSENTIEL_TOURNEE_WINDOW = timedelta(hours=24)

# Valeur de `DigestTopicArticle.badge` qui marque l'article comme "Actu du jour".
_BADGE_ACTU = "actu"

# Poids du scoring composite — réglés pour que chaque levier puisse l'emporter
# isolément sans qu'aucun ne phagocyte les autres. Toute modif → ajouter un
# test dans `test_essentiel_endpoint.py`.
# Source de vérité partagée avec le digest topics et le feed thématique
# (`ScoringWeights.TOPIC_IS_TRENDING_BONUS` / `TOPIC_IS_UNE_BONUS`).
_W_TRENDING = ScoringWeights.TOPIC_IS_TRENDING_BONUS  # 50 — topic.is_trending
_W_UNE = ScoringWeights.TOPIC_IS_UNE_BONUS  # 35 — topic.is_une
_W_BADGE_ACTU = 25.0  # article.badge == _BADGE_ACTU (signal explicite du digest)
_W_FOLLOWED_SOURCE = 100.0
_W_FOLLOWED_SOURCE_FLAG = 50.0  # bonus moindre si on n'a que le flag du digest
_W_TOPIC_WEIGHT = 50.0
_W_RANK_PENALTY = 0.5
_W_READ_PENALTY = 1000.0  # Écarte les articles déjà lus sauf si rien d'autre.

# Source types exclus du pool Essentiel — Reddit est un agrégateur, pas une
# rédaction d'info.
_EXCLUDED_SOURCE_TYPES: frozenset[SourceType] = frozenset({SourceType.REDDIT})


@dataclass(frozen=True)
class EssentielUserContext:
    """Préférences user nécessaires pour re-ranker l'Essentiel.

    Toujours instanciable vide → fallback gracieux quand l'utilisateur n'a
    pas (encore) de prefs explicites.
    """

    followed_source_ids: frozenset[UUID] = field(default_factory=frozenset)
    source_priority_multipliers: dict[UUID, float] = field(default_factory=dict)
    topic_weights: dict[str, float] = field(default_factory=dict)
    # Préférence langue : si True, on masque les articles des sources
    # non-FR (sauf si la source est explicitement suivie).
    hide_non_fr_sources: bool = False
    # Mutes (`user_personalization`) appliqués en tête de pipeline avant
    # tout autre filtre — un article muté ne doit jamais devenir le fallback
    # Tournée ni être proposé en lead Actu.
    muted_themes: frozenset[str] = field(default_factory=frozenset)
    muted_topic_slugs: frozenset[str] = field(default_factory=frozenset)
    muted_source_ids: frozenset[UUID] = field(default_factory=frozenset)


async def fetch_user_essentiel_context(
    db: AsyncSession, user_id: UUID
) -> EssentielUserContext:
    """Charge en read-only les signaux user utiles à l'Essentiel.

    Aucune écriture, aucun pipeline LLM. 1 SELECT court, indexé sur
    `user_id`. Sans hit (utilisateur sans prefs) : retourne un contexte vide.
    """
    row = (
        (
            await db.execute(
                text(
                    """
                SELECT
                    COALESCE(
                        (
                            SELECT jsonb_agg(
                                jsonb_build_object(
                                    'source_id', source_id::text,
                                    'priority_multiplier', COALESCE(priority_multiplier, 1.0)
                                )
                            )
                            FROM user_sources
                            WHERE user_id = :user_id
                              AND state IN (:followed_state, :favorite_state)
                        ),
                        '[]'::jsonb
                    ) AS sources,
                    COALESCE(
                        (
                            SELECT jsonb_agg(
                                jsonb_build_object(
                                    'slug', interest_slug,
                                    'weight', COALESCE(weight, 1.0)
                                )
                            )
                            FROM user_interests
                            WHERE user_id = :user_id
                        ),
                        '[]'::jsonb
                    ) AS interests,
                    COALESCE(
                        (
                            SELECT jsonb_agg(
                                jsonb_build_object(
                                    'slug', topic_slug,
                                    'weight', COALESCE(weight, 1.0)
                                )
                            )
                            FROM user_subtopics
                            WHERE user_id = :user_id
                        ),
                        '[]'::jsonb
                    ) AS subtopics,
                    COALESCE(
                        (
                            SELECT jsonb_build_object(
                                'hide_non_fr_sources', COALESCE(hide_non_fr_sources, true),
                                'muted_themes', COALESCE(to_jsonb(muted_themes), '[]'::jsonb),
                                'muted_topics', COALESCE(to_jsonb(muted_topics), '[]'::jsonb),
                                'muted_sources', COALESCE(to_jsonb(muted_sources), '[]'::jsonb)
                            )
                            FROM user_personalization
                            WHERE user_id = :user_id
                        ),
                        jsonb_build_object(
                            'hide_non_fr_sources', true,
                            'muted_themes', '[]'::jsonb,
                            'muted_topics', '[]'::jsonb,
                            'muted_sources', '[]'::jsonb
                        )
                    ) AS personalization
                """
                ),
                {
                    "user_id": user_id,
                    "followed_state": InterestState.FOLLOWED.value,
                    "favorite_state": InterestState.FAVORITE.value,
                },
            )
        )
        .mappings()
        .one()
    )

    src_rows = row["sources"] or []
    followed_source_ids = frozenset(UUID(src["source_id"]) for src in src_rows)
    source_priority_multipliers = {
        UUID(src["source_id"]): float(src.get("priority_multiplier") or 1.0)
        for src in src_rows
    }

    topic_weights: dict[str, float] = {}

    for interest in row["interests"] or []:
        slug = interest.get("slug")
        if slug:
            topic_weights[slug] = max(
                topic_weights.get(slug, 0.0), float(interest.get("weight") or 1.0)
            )

    for subtopic in row["subtopics"] or []:
        slug = subtopic.get("slug")
        if slug:
            topic_weights[slug] = max(
                topic_weights.get(slug, 0.0), float(subtopic.get("weight") or 1.0)
            )

    personalization = row["personalization"] or {}
    hide_non_fr_sources = bool(personalization.get("hide_non_fr_sources", True))
    muted_themes = frozenset(personalization.get("muted_themes") or ())
    muted_topic_slugs = frozenset(personalization.get("muted_topics") or ())
    muted_source_ids = frozenset(
        UUID(source_id) for source_id in (personalization.get("muted_sources") or ())
    )

    return EssentielUserContext(
        followed_source_ids=followed_source_ids,
        source_priority_multipliers=source_priority_multipliers,
        topic_weights=topic_weights,
        hide_non_fr_sources=hide_non_fr_sources,
        muted_themes=muted_themes,
        muted_topic_slugs=muted_topic_slugs,
        muted_source_ids=muted_source_ids,
    )


def _source_letter(name: str) -> str:
    """Initiale (uppercase) de la source pour la pastille mobile."""
    for ch in name.strip():
        if ch.isalnum():
            return ch.upper()
    return "?"


def _is_actu_du_jour(topic: DigestTopic, article: DigestTopicArticle) -> bool:
    """Un article est "Actu du jour" si son topic est trending/une ou si
    le digest l'a explicitement marqué d'un badge "actu"."""
    return bool(topic.is_trending or topic.is_une or article.badge == _BADGE_ACTU)


def _is_sport_pick(topic: DigestTopic, article: DigestTopicArticle) -> bool:
    """Détecte un article sport (union de signaux).

    Couvre le cas TrashTalk : `source.theme="society"` mais `content.theme="sport"`.
    Cherche dans :
    - `topic.theme` (signal éditorial du digest)
    - `article.source.theme` (catégorisation source)
    - `article.topics[]` (classification ML Mistral)
    - keywords titre (NBA, Ligue des champions, F1, etc.)
    """
    candidates = {
        (topic.theme or "").lower(),
        (article.source.theme or "").lower(),
    }
    if candidates & LOW_PRIORITY_SPORT_THEMES:
        return True
    if article.topics and any(
        isinstance(t, str) and t.lower() == "sport" for t in article.topics
    ):
        return True
    text = (article.title or "").lower()
    return any(kw in text for kw in LOW_PRIORITY_SPORT_KEYWORDS)


def _is_allowed_for_essentiel(article: DigestTopicArticle) -> bool:
    """Pré-filtre : un article passe-t-il les critères de l'Essentiel ?

    Exclut (Story 9.4) :
    - Podcasts et vidéos YouTube (content_type ∈ {PODCAST, YOUTUBE}).
    - Sources Reddit (agrégateurs, pas une rédaction d'info).
    - Bulletins radio + chroniques régulières par pattern de titre
      (« JOURNAL DE 8H », « Avec Sciences, chronique du… »).
    """
    if article.content_type != ContentType.ARTICLE:
        return False
    if (article.source.type or "").lower() in _EXCLUDED_SOURCE_TYPES:
        return False
    return not is_news_bulletin_title(article.title)


def _filter_articles_allowed(topics: list[DigestTopic]) -> list[DigestTopic]:
    """Recopie les topics en ne gardant que les articles autorisés.

    Topics dont tous les articles sont exclus disparaissent. `model_copy`
    évite de muter la `DigestResponse` source (potentiellement cachée).
    """
    filtered: list[DigestTopic] = []
    for topic in topics:
        kept = [a for a in topic.articles if _is_allowed_for_essentiel(a)]
        if kept:
            filtered.append(topic.model_copy(update={"articles": kept}))
    return filtered


def _perspective_score(perspective_count: int) -> float:
    """Score non-linéaire des perspectives (Story 9.4).

    Délègue à `helpers.compute_coverage_score` — source de vérité partagée
    avec le feed thématique (`PertinencePillar._score_coverage`).
    """
    return compute_coverage_score(perspective_count)


def _is_followed_topic(topic: DigestTopic, ctx: EssentielUserContext) -> bool:
    return bool(topic.theme and topic.theme in ctx.topic_weights)


def _is_followed_source(article: DigestTopicArticle, ctx: EssentielUserContext) -> bool:
    return article.source.id in ctx.followed_source_ids or article.is_followed_source


def _score_article(
    topic: DigestTopic,
    article: DigestTopicArticle,
    ctx: EssentielUserContext,
) -> float:
    """Score composite user-aware d'un article candidat de l'Essentiel.

    Réutilise les signaux déjà calculés par le digest (trending/une/badge actu/
    is_followed_source) et leur applique des coefficients alignés sur ceux du
    briefing (`Top3Selector`).
    """
    score = 0.0

    # Boost Actu du jour (aligné Top3Selector).
    if topic.is_trending:
        score += _W_TRENDING
    if topic.is_une:
        score += _W_UNE
    if article.badge == _BADGE_ACTU:
        score += _W_BADGE_ACTU

    # Bonus source suivie : préfère la jointure DB-fraîche (followed_source_ids).
    # Fallback sur le flag pré-calculé du digest si le contexte user est vide.
    if article.source.id in ctx.followed_source_ids:
        multiplier = ctx.source_priority_multipliers.get(article.source.id, 1.0)
        score += _W_FOLLOWED_SOURCE * multiplier
    elif article.is_followed_source:
        score += _W_FOLLOWED_SOURCE_FLAG

    # Bonus topic suivi (poids utilisateur).
    if topic.theme and topic.theme in ctx.topic_weights:
        score += _W_TOPIC_WEIGHT * ctx.topic_weights[topic.theme]

    # Bonus "transversal" log-calibré : un sujet à 6+ médias bat un signal
    # trending faible, un scoop isolé n'a aucun bonus.
    score += _perspective_score(int(topic.perspective_count or 0))

    # Pénalité is_read : écarte les articles déjà lus sauf si rien d'autre.
    if article.is_read:
        score -= _W_READ_PENALTY

    # Tie-break : un article rank=1 reste préféré à rank=2 à signaux égaux.
    score -= _W_RANK_PENALTY * float(article.rank)

    return score


def _filter_articles_by_mutes(
    topics: list[DigestTopic],
    ctx: EssentielUserContext,
) -> list[DigestTopic]:
    """Retire les articles mutés par l'utilisateur (`user_personalization`).

    Trois leviers :
    - `muted_themes` (slugs macro comme "tech", "international") → topic entier
      écarté si `topic.theme` est muté.
    - `muted_source_ids` (UUID des sources) → article écarté.
    - `muted_topic_slugs` (slugs granulaires ML) → article écarté si
      `article.topics` intersecte la liste.

    Appliqué *avant* tout autre filtre — un article muté ne doit jamais devenir
    le fallback Tournée ni être proposé en lead Actu.
    """
    if not (ctx.muted_themes or ctx.muted_source_ids or ctx.muted_topic_slugs):
        return topics

    filtered: list[DigestTopic] = []
    for topic in topics:
        if topic.theme and topic.theme in ctx.muted_themes:
            continue
        kept = [
            a
            for a in topic.articles
            if a.source.id not in ctx.muted_source_ids
            and not (ctx.muted_topic_slugs.intersection(a.topics))
        ]
        if kept:
            filtered.append(topic.model_copy(update={"articles": kept}))
    return filtered


def _filter_articles_by_language(
    topics: list[DigestTopic],
    ctx: EssentielUserContext,
) -> list[DigestTopic]:
    """Retire les articles de sources non-FR non-suivies si le toggle est ON.

    Recopie chaque topic via `model_copy` pour ne pas muter la
    `DigestResponse` source (la même instance peut être servie sur
    plusieurs requêtes en cas de cache amont).
    """
    if not ctx.hide_non_fr_sources:
        return topics

    filtered: list[DigestTopic] = []
    for topic in topics:
        kept = [
            a
            for a in topic.articles
            if a.source.id in ctx.followed_source_ids
            or not is_foreign_source(a.source.language)
        ]
        if kept:
            filtered.append(topic.model_copy(update={"articles": kept}))
    return filtered


def _filter_articles_by_freshness(
    topics: list[DigestTopic],
    *,
    now: datetime | None = None,
) -> list[DigestTopic]:
    """Conserve uniquement les articles publiés dans les dernières 24 heures."""
    cutoff = (now or datetime.now(UTC)) - ESSENTIEL_TOURNEE_WINDOW
    filtered: list[DigestTopic] = []
    for topic in topics:
        kept = [a for a in topic.articles if a.published_at >= cutoff]
        if kept:
            filtered.append(topic.model_copy(update={"articles": kept}))
    return filtered


def _filter_articles_by_followed_sources(
    topics: list[DigestTopic],
    ctx: EssentielUserContext,
) -> list[DigestTopic]:
    """Construit le tier prioritaire des sources explicitement suivies."""
    if not ctx.followed_source_ids:
        return []

    filtered: list[DigestTopic] = []
    for topic in topics:
        kept = [
            article
            for article in topic.articles
            if article.source.id in ctx.followed_source_ids
        ]
        if kept:
            filtered.append(topic.model_copy(update={"articles": kept}))
    return filtered


def _pick_transversal_articles(
    topics: list[DigestTopic],
    ctx: EssentielUserContext,
    *,
    now: datetime | None = None,
) -> list[tuple[DigestTopic, DigestTopicArticle]]:
    """Pioche jusqu'à 5 articles cross-topic, user-aware.

    1. Applique définitivement mutes, langue, types interdits et fraîcheur 24 h.
    2. Sélectionne le tier sources suivies, puis complète depuis le pool global.
    3. Déduplique les sujets et limite chaque source à deux articles.
    4. Diffère le sport jusqu'au cinquième slot, sans post-filtre destructif.
    """
    # Mutes utilisateur (`user_personalization`) — prime sur tous les autres
    # filtres : un article muté ne doit jamais devenir le fallback Tournée.
    topics = _filter_articles_by_mutes(topics, ctx)
    topics = _filter_articles_by_language(topics, ctx)
    # Story 9.4 : exclure podcasts/youtube/reddit/bulletins en tête de pipeline
    # — ces contenus ne reflètent pas l'actualité chaude traitée par la presse.
    topics = _filter_articles_allowed(topics)

    hard_filtered_count = sum(len(topic.articles) for topic in topics)
    fresh_topics = _filter_articles_by_freshness(topics, now=now)
    followed_topics = _filter_articles_by_followed_sources(fresh_topics, ctx)
    fresh_count = sum(len(topic.articles) for topic in fresh_topics)
    followed_count = sum(len(topic.articles) for topic in followed_topics)

    if not fresh_topics:
        logger.info(
            "essentiel_selection hard_filtered=%d followed_pool=%d "
            "fresh_global_pool=%d supplements=0 dedup_rejections=0 "
            "sport_rejections=0 final_count=0",
            hard_filtered_count,
            followed_count,
            fresh_count,
        )
        return []

    # Score de chaque (topic, article) une seule fois sur le pool global frais.
    scored: dict[tuple[str, UUID], float] = {}
    for topic in fresh_topics:
        for article in topic.articles:
            scored[(topic.topic_id, article.content_id)] = _score_article(
                topic, article, ctx
            )

    picked: list[tuple[DigestTopic, DigestTopicArticle]] = []
    seen_content_ids: set[UUID] = set()
    used_topics: set[str] = set()
    source_count: dict[UUID, int] = {}
    picked_title_tokens: list[set[str]] = []
    dedup_rejections = 0
    sport_rejections = 0

    def _is_duplicate_subject(topic: DigestTopic, article: DigestTopicArticle) -> bool:
        """Un même sujet ne doit jamais occuper deux slots de l'Essentiel.

        L'Essentiel est une sélection *transversale* (1 article par sujet). On
        bloque sur deux niveaux complémentaires :
        - `topic.topic_id` déjà servi → un topic « revue de presse » multi-sources
          (ex: météore couvert par 3 médias) ne peut ré-entrer via un round de
          remplissage.
        - similarité de titre Jaccard ≥ `TOPIC_CLUSTER_THRESHOLD` → filet pour les
          clusters scindés ou le couple actu/deep d'un même sujet, dont les titres
          quasi-identiques tomberaient sinon sur des `topic_id` différents.
        """
        if topic.topic_id in used_topics:
            return True
        tokens = normalize_title(article.title)
        if tokens:
            for prev in picked_title_tokens:
                if (
                    jaccard_similarity(tokens, prev)
                    >= ScoringWeights.TOPIC_CLUSTER_THRESHOLD
                ):
                    return True
        return False

    def _try_pick(topic: DigestTopic, article: DigestTopicArticle) -> bool:
        """Tente d'ajouter un article en respectant dédup + diversité source.

        Renvoie True si ajouté, False sinon. Marque les ensembles.
        """
        nonlocal dedup_rejections, sport_rejections

        if article.content_id in seen_content_ids:
            dedup_rejections += 1
            return False
        if source_count.get(article.source.id, 0) >= ESSENTIEL_MAX_PER_SOURCE:
            return False
        if _is_duplicate_subject(topic, article):
            dedup_rejections += 1
            return False
        if _is_sport_pick(topic, article):
            non_sport_count = sum(
                not _is_sport_pick(picked_topic, picked_article)
                for picked_topic, picked_article in picked
            )
            already_has_sport = any(
                _is_sport_pick(picked_topic, picked_article)
                for picked_topic, picked_article in picked
            )
            if (
                non_sport_count < ScoringWeights.ESSENTIEL_SPORT_MIN_SLOT - 1
                or already_has_sport
            ):
                sport_rejections += 1
                return False
        if len(picked) >= ESSENTIEL_MAX_ARTICLES:
            return False
        picked.append((topic, article))
        seen_content_ids.add(article.content_id)
        used_topics.add(topic.topic_id)
        source_count[article.source.id] = source_count.get(article.source.id, 0) + 1
        picked_title_tokens.append(normalize_title(article.title))
        return True

    def _ordered_candidates(
        tier_topics: list[DigestTopic],
    ) -> list[tuple[DigestTopic, DigestTopicArticle, float]]:
        candidates = [
            (topic, article, scored[(topic.topic_id, article.content_id)])
            for topic in tier_topics
            for article in topic.articles
        ]
        return sorted(
            candidates,
            key=lambda item: (
                not _is_actu_du_jour(item[0], item[1]),
                -item[2],
                item[0].rank,
                item[1].rank,
            ),
        )

    def _fill_from_tier(tier_topics: list[DigestTopic]) -> None:
        candidates = _ordered_candidates(tier_topics)
        # Sport is reconsidered only after every non-sport candidate. This
        # prevents a high-scoring sport item from consuming a slot that would
        # disappear during a final post-filter.
        for want_sport in (False, True):
            for topic, article, _ in candidates:
                if _is_sport_pick(topic, article) != want_sport:
                    continue
                _try_pick(topic, article)
                if len(picked) >= ESSENTIEL_MAX_ARTICLES:
                    return

    _fill_from_tier(followed_topics)
    followed_pick_count = len(picked)
    if len(picked) < ESSENTIEL_MAX_ARTICLES:
        _fill_from_tier(fresh_topics)

    # `picked` only grows after `followed_pick_count` is captured, so the
    # supplement count is always non-negative.
    supplements = len(picked) - followed_pick_count
    logger.info(
        "essentiel_selection hard_filtered=%d followed_pool=%d "
        "fresh_global_pool=%d supplements=%d dedup_rejections=%d "
        "sport_rejections=%d final_count=%d",
        hard_filtered_count,
        followed_count,
        fresh_count,
        supplements,
        dedup_rejections,
        sport_rejections,
        len(picked),
    )
    return picked


def _to_essentiel_article(
    topic: DigestTopic,
    article: DigestTopicArticle,
    rank: int,
    ctx: EssentielUserContext,
) -> EssentielArticle:
    return EssentielArticle(
        content_id=article.content_id,
        title=article.title,
        url=article.url,
        description=article.description,
        thumbnail_url=article.thumbnail_url,
        published_at=article.published_at,
        source=article.source,
        source_letter=_source_letter(article.source.name),
        kind=EssentielKind.THEME,
        theme=topic.theme,
        section_label=topic.label,
        perspective_count=topic.perspective_count,
        rank=rank,
        is_read=article.is_read,
        is_saved=article.is_saved,
        is_liked=article.is_liked,
        is_dismissed=article.is_dismissed,
        is_followed_source=_is_followed_source(article, ctx),
        is_followed_topic=_is_followed_topic(topic, ctx),
        is_actu_du_jour=_is_actu_du_jour(topic, article),
    )


def build_essentiel_response(
    digest: DigestResponse,
    user_context: EssentielUserContext | None = None,
    *,
    now: datetime | None = None,
) -> EssentielResponse:
    """Projette une `DigestResponse` en `EssentielResponse` (5 articles max).

    Si `user_context` est None, on utilise un contexte vide → fallback
    no-prefs (le scorer dégénère en actu_boost + perspective − rank).
    """
    ctx = user_context or EssentielUserContext()
    picks = _pick_transversal_articles(digest.topics, ctx, now=now)
    articles = [
        _to_essentiel_article(topic, article, rank=i + 1, ctx=ctx)
        for i, (topic, article) in enumerate(picks)
    ]
    return EssentielResponse(
        target_date=digest.target_date,
        generated_at=digest.generated_at,
        articles=articles,
        is_stale_fallback=digest.is_stale_fallback,
    )


def _content_to_essentiel_article(
    content: Content,
    rank: int,
    ctx: EssentielUserContext,
) -> EssentielArticle:
    """Projette un `Content` brut (complément sources suivies) en EssentielArticle.

    Utilisé par le fallback de complétion quand le digest produit < 3 articles.
    L'article vient forcément d'une source suivie/favorite → `is_followed_source`
    est toujours vrai ; pas de topic transversal d'origine, on retombe sur le nom
    de la source comme libellé de section et `perspective_count=0`.
    """
    source = SourceMini.model_validate(content.source)
    return EssentielArticle(
        content_id=content.id,
        title=content.title,
        url=content.url,
        description=content.description,
        thumbnail_url=content.thumbnail_url,
        published_at=content.published_at,
        source=source,
        source_letter=_source_letter(content.source.name),
        kind=EssentielKind.THEME,
        theme=content.theme,
        section_label=content.source.name,
        perspective_count=0,
        rank=rank,
        is_followed_source=True,
        is_followed_topic=bool(content.theme and content.theme in ctx.topic_weights),
        is_actu_du_jour=False,
        language=content.language,
    )


async def _fetch_followed_source_supplements(
    db: AsyncSession,
    user_id: UUID,
    ctx: EssentielUserContext,
    *,
    is_serene: bool,
    existing: list[EssentielArticle],
    limit: int,
    now: datetime | None = None,
) -> list[EssentielArticle]:
    """Complète l'Essentiel avec des articles frais des sources suivies/favorites.

    Déclenché quand le digest produit moins de `ESSENTIEL_MIN_ARTICLES`. Pour
    borner la surface éditoriale, on ne pioche que dans les sources explicitement
    suivies/favorites (`followed_source_ids`), fenêtre de fraîcheur commune
    (`ESSENTIEL_TOURNEE_WINDOW`), en excluant :
    - contenus lus (`status == CONSUMED`) ou masqués (`is_hidden`),
    - sources mutées et sujets mutés (`muted_topic_slugs`),
    - doublons de contenu/source (cap 2/source)/sujet déjà présents,
    - en mode serein, tout `Content.is_serene != True`,
    - podcasts/vidéos/Reddit/bulletins (mêmes critères que le digest).
    """
    if limit <= 0:
        return []
    candidate_source_ids = list(ctx.followed_source_ids - ctx.muted_source_ids)
    if not candidate_source_ids:
        return []

    cutoff = (now or datetime.now(UTC)) - ESSENTIEL_TOURNEE_WINDOW
    already_read_or_hidden = exists().where(
        UserContentStatus.content_id == Content.id,
        UserContentStatus.user_id == user_id,
        or_(
            UserContentStatus.is_hidden,
            UserContentStatus.status == ContentStatus.CONSUMED,
        ),
    )

    query = (
        select(Content)
        .join(Content.source)
        .options(selectinload(Content.source))
        .where(Content.source_id.in_(candidate_source_ids))
        .where(Content.published_at >= cutoff)
        .where(Content.content_type == ContentType.ARTICLE)
        .where(~already_read_or_hidden)
        .where(Source.is_active.is_(True))
        .order_by(Content.published_at.desc())
        .limit(ESSENTIEL_SUPPLEMENT_CANDIDATE_CAP)
    )
    if is_serene:
        query = query.where(Content.is_serene.is_(True))

    candidates = (await db.execute(query)).scalars().all()
    if not candidates:
        return []

    # Dédup contre les articles déjà retenus (digest) : content_id, cap source,
    # similarité de titre — mêmes garde-fous que `_pick_transversal_articles`.
    seen_content_ids = {a.content_id for a in existing}
    source_count: dict[UUID, int] = {}
    for article in existing:
        source_count[article.source.id] = source_count.get(article.source.id, 0) + 1
    picked_title_tokens = [normalize_title(a.title) for a in existing if a.title]

    supplements: list[EssentielArticle] = []
    rank = len(existing) + 1
    for content in candidates:
        if len(supplements) >= limit:
            break
        if content.id in seen_content_ids:
            continue
        source = content.source
        if (source.type or "").lower() in _EXCLUDED_SOURCE_TYPES:
            continue
        if is_news_bulletin_title(content.title):
            continue
        if ctx.muted_topic_slugs and ctx.muted_topic_slugs.intersection(
            content.topics or ()
        ):
            continue
        if source_count.get(source.id, 0) >= ESSENTIEL_MAX_PER_SOURCE:
            continue
        tokens = normalize_title(content.title)
        if tokens and any(
            jaccard_similarity(tokens, prev) >= ScoringWeights.TOPIC_CLUSTER_THRESHOLD
            for prev in picked_title_tokens
            if prev
        ):
            continue
        supplements.append(_content_to_essentiel_article(content, rank, ctx))
        seen_content_ids.add(content.id)
        source_count[source.id] = source_count.get(source.id, 0) + 1
        picked_title_tokens.append(tokens)
        rank += 1

    return supplements


async def build_essentiel_response_with_supplements(
    db: AsyncSession,
    user_id: UUID,
    digest: DigestResponse,
    *,
    user_context: EssentielUserContext,
    is_serene: bool,
    now: datetime | None = None,
) -> EssentielResponse:
    """Construit l'Essentiel depuis le digest, puis complète si < 3 articles.

    1. Projection digest → jusqu'à 5 articles transversaux (logique historique).
    2. Si le résultat est < `ESSENTIEL_MIN_ARTICLES`, complète jusqu'à
       `ESSENTIEL_MAX_ARTICLES` avec des articles frais des sources suivies.
    3. Le router décide ensuite du 202 ``preparing`` si le total reste < 3.
    """
    response = build_essentiel_response(digest, user_context=user_context, now=now)
    if len(response.articles) >= ESSENTIEL_MIN_ARTICLES:
        return response

    supplements = await _fetch_followed_source_supplements(
        db,
        user_id,
        user_context,
        is_serene=is_serene,
        existing=response.articles,
        limit=ESSENTIEL_MAX_ARTICLES - len(response.articles),
        now=now,
    )
    if not supplements:
        return response

    merged = list(response.articles) + supplements
    logger.info(
        "essentiel_supplemented digest_count=%d supplements=%d final_count=%d",
        len(response.articles),
        len(supplements),
        len(merged),
    )
    return response.model_copy(update={"articles": merged})
