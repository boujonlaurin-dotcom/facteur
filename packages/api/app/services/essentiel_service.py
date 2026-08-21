"""Service `essentiel` — top 5 articles transversaux du jour.

Strictement read-only : consomme la `DigestResponse` déjà calculée par la cron
nocturne via `read_digest_or_fallback`, et la projette en 5 articles cross-topic
pour la carte hi-fi "L'Essentiel du jour" du feed mobile.

Architecture (PR 4, bug-curation-essentiel-personnalisation) :
- Le `PillarScoringEngine` et le `digest_selector` ont déjà scoré chaque actu
  de sujet en amont ; le score est persisté dans le snapshot et remonte via
  `DigestTopicArticle.pillar_score`. Ce service est un **adaptateur** : il
  rejoue la même formule que la clé v4 du digest
  (`digest_selector.mixed_subject_rank_score`), via les mêmes helpers
  (`helpers/editorial_ranking`) — aucun re-scoring, aucun barème parallèle.
- `_score_article` = `(1-w)·importance_100 + w·perso_100`
  (+ `ESSENTIEL_UNE_BONUS` si `is_une`, − éviction lu, − tie-break rang).
  `perso = pillar_score` (None → médiane du pool, ni enterré ni boosté).

Reste volontairement HORS moteur (spécifique à la surface Essentiel) :
- éviction des articles lus + fenêtre de grâce 30 min (`_is_within_read_grace`),
- déduplication de sujet (topic_id + similarité Jaccard des titres),
- caps de diversité (1/source, fallback 2) et plafond 5 articles,
- différé sport (jamais avant le slot 5, 1 max),
- filtres durs (mutes, langue, types interdits, bulletins, fraîcheur 24 h),
- tie-break par rang digest,
- tiers « sources suivies d'abord » (`_fill_from_tier(followed_topics)`) — la
  préférence source suivie survit structurellement ; le bonus chiffré, lui,
  est déjà dans `pillar_score` (le ré-empiler = double-comptage).

Fallback digest legacy (sans `score` persisté) : perso neutre partout → le
score dégénère proprement en importance éditoriale pure.
"""

import logging
import statistics
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
from app.services.recommendation.helpers.editorial_ranking import (
    blended_subject_score,
)
from app.services.recommendation.scoring_config import ScoringWeights
from app.services.text_similarity import jaccard_similarity, normalize_title
from app.utils.time import PARIS_TZ

logger = logging.getLogger(__name__)

ESSENTIEL_MAX_ARTICLES = 5
# Diversité dure : au plus 1 article par source. Relâché à 2 (``_MAX_PER_SOURCE_FALLBACK``)
# en 2e passe quand le pool de sources distinctes ne suffit pas à remplir les 5
# slots — évite une carte pauvre / un ``202 preparing``. Même logique que
# ``DigestSelector._select_with_diversity`` (fallback source si trop peu de sources).
ESSENTIEL_MAX_PER_SOURCE = 1
_MAX_PER_SOURCE_FALLBACK = 2

# Plancher de qualité : en-dessous de ce nombre d'articles issus du digest, on
# complète depuis les sources suivies/favorites de l'utilisateur ; si le total
# reste < ESSENTIEL_MIN_ARTICLES, le router renvoie 202 ``preparing`` plutôt
# qu'une carte pauvre (1-2 articles).
ESSENTIEL_MIN_ARTICLES = 3
# Taille du pool de candidats frais piochés dans les sources suivies pour la
# complétion — borne le SELECT, on ne garde au plus que les slots manquants.
ESSENTIEL_SUPPLEMENT_CANDIDATE_CAP = 30

# Cap dédié à ``GET /api/essentiel/more`` (Story 33.4). Le blend du digest
# cherche 1 à 3 slots manquants et 30 candidats lui suffisent ; « Plus
# d'articles ? » alimente une pile qui peut tourner toute la journée, avec des
# exclusions qui grossissent à chaque tour. 80 laisse de la marge après la dédup
# titre et le cap par source, sans faire du SELECT un scan.
ESSENTIEL_MORE_CANDIDATE_CAP = 80

# Plafond d'affichage du delta « N nouveaux depuis ce matin » sur le héros
# mobile (au-delà, le client affiche « 9+ »). Borne aussi le comptage pour ne
# jamais suggérer un feed infini.
_ESSENTIEL_DELTA_CAP = 9

# Fenêtre de fraîcheur commune aux deux tiers de sélection. Les sources
# suivies sont prioritaires, puis le pool éditorial global frais complète.
ESSENTIEL_TOURNEE_WINDOW = timedelta(hours=24)

# Paliers de fenêtre pour ``GET /api/essentiel/more`` (Story 33.4). On reste sur
# 24 h tant que ça suffit — l'``ORDER BY published_at DESC`` garde la fraîcheur
# en tête du lot — et on n'élargit que si le pool ne rend pas ``limit``. Un
# article de 40 h vaut mieux qu'une pile qui sèche à mi-parcours.
ESSENTIEL_MORE_WINDOW_STEPS: tuple[timedelta, ...] = (
    timedelta(hours=24),
    timedelta(hours=48),
    timedelta(hours=72),
)

# Fenêtre de grâce après lecture : "Essentiel vivant" (story 9.8) évince
# activement tout article lu de la réponse `GET /api/essentiel` pour laisser
# la place à du contenu frais. Mais l'app relance `_fetchAll()` sans cooldown
# à chaque cold start, ce qui évince quasi systématiquement l'article qu'on
# vient de lire avant que l'utilisateur n'ait pu voir la coche persister.
# On protège donc un article tout juste lu de l'éviction pendant cette durée.
ESSENTIEL_READ_EVICTION_GRACE = timedelta(minutes=30)

# Valeur de `DigestTopicArticle.badge` qui marque l'article comme "Actu du jour".
_BADGE_ACTU = "actu"

# Poids résiduels hors moteur. Le score principal vient du mélange
# `blended_subject_score` (le même helper que la clé v4 du digest) ; ne restent
# ici que les leviers propres à la surface Essentiel.
# `_W_FOLLOWED_SOURCE` / `_W_TOPIC_WEIGHT` : perso brute du recall live
# (`_score_live_candidate`) — les candidats frais n'ont pas de pillar_score.
_W_FOLLOWED_SOURCE = 100.0
_W_TOPIC_WEIGHT = 50.0
_W_RANK_PENALTY = 0.5
_ESSENTIEL_READ_EVICTION = 1000.0  # Écarte les lus sauf si rien d'autre.

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


def _is_followed_topic(topic: DigestTopic, ctx: EssentielUserContext) -> bool:
    return bool(topic.theme and topic.theme in ctx.topic_weights)


def _is_followed_source(article: DigestTopicArticle, ctx: EssentielUserContext) -> bool:
    return article.source.id in ctx.followed_source_ids or article.is_followed_source


def _score_article(
    topic: DigestTopic,
    article: DigestTopicArticle,
    *,
    neutral: float = 0.0,
    now: datetime | None = None,
) -> float:
    """Score d'un candidat Essentiel — MÊME formule que la clé v4 du digest.

    `blended_subject_score(...)` — le même helper que
    `digest_selector.mixed_subject_rank_score` (test de parité dédié). Les
    bonus source-suivie/thème ne sont PAS ré-empilés : ils sont déjà dans
    `pillar_score` (les rajouter = double-comptage) ; la préférence source
    suivie survit structurellement via le tier `_fill_from_tier(followed_topics)`.

    `neutral` = valeur perso des articles sans `pillar_score` (extras, digests
    legacy) — la médiane du pool en pratique, ni enterrés ni boostés.
    """
    # Fallback legacy : les vieux snapshots n'ont pas `source_count` mais
    # portent `perspective_count` (même ordre de grandeur de couverture).
    effective_sources = topic.source_count or int(topic.perspective_count or 0)
    score = blended_subject_score(
        effective_sources,
        article.published_at,
        topic.divergence_level,
        article.pillar_score,
        neutral=neutral,
        now=now,
    )

    # Seul bonus éditorial hors moteur : la décision « À la Une ».
    if topic.is_une:
        score += ScoringWeights.ESSENTIEL_UNE_BONUS

    # Éviction des lus : écarte les articles déjà lus sauf si rien d'autre.
    if article.is_read:
        score -= _ESSENTIEL_READ_EVICTION

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
    # `neutral` = médiane des pillar_score du pool : un article sans score
    # persisté (extras, digest legacy) est traité comme « moyen », jamais
    # enterré ni boosté. Digest 100 % legacy → 0.0 partout ⇒ dégénérescence
    # propre en importance éditoriale pure. `now` figé une fois : tous les
    # candidats partagent la même référence de récence.
    pool_scores = [
        article.pillar_score
        for topic in fresh_topics
        for article in topic.articles
        if article.pillar_score is not None
    ]
    neutral = statistics.median(pool_scores) if pool_scores else 0.0
    now_ref = now or datetime.now(UTC)
    scored: dict[tuple[str, UUID], float] = {}
    for topic in fresh_topics:
        for article in topic.articles:
            scored[(topic.topic_id, article.content_id)] = _score_article(
                topic, article, neutral=neutral, now=now_ref
            )

    picked: list[tuple[DigestTopic, DigestTopicArticle]] = []
    seen_content_ids: set[UUID] = set()
    used_topics: set[str] = set()
    source_count: dict[UUID, int] = {}
    picked_title_tokens: list[set[str]] = []
    dedup_rejections = 0
    sport_rejections = 0
    # Cap source courant : 1 en 1re passe (diversité dure), relâché à 2 si le
    # pool de sources distinctes ne suffit pas à remplir les 5 slots (cf. plus
    # bas). Lu comme variable libre par `_try_pick`.
    max_per_source = ESSENTIEL_MAX_PER_SOURCE

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
        if source_count.get(article.source.id, 0) >= max_per_source:
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
        # Plus de préfixe `_is_actu_du_jour` : le badge "actu" est écrit
        # inconditionnellement par le digest (signal universel = no-op en
        # prod), le score mixte porte seul l'ordre.
        return sorted(
            candidates,
            key=lambda item: (-item[2], item[0].rank, item[1].rank),
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

    # Fallback diversité : le cap 1/source n'a pas rempli les 5 slots (trop peu
    # de sources distinctes dans le pool). On relâche à 2/source et on complète.
    # Les articles déjà retenus restent (idempotent : ils sont re-rejetés par
    # `seen_content_ids`/`used_topics`), seuls des 2es articles d'un NOUVEAU
    # sujet peuvent entrer — la diversité de sujet reste garantie.
    if (
        len(picked) < ESSENTIEL_MAX_ARTICLES
        and max_per_source < _MAX_PER_SOURCE_FALLBACK
    ):
        max_per_source = _MAX_PER_SOURCE_FALLBACK
        _fill_from_tier(followed_topics)
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


# Cap d'émission des sources de perspective : la carte n'en rend que 3 et
# chaque entrée porte un `logo_url` (une requête image chacune). Le pipeline
# en produit jusqu'à 6 — sans ce cap, l'écran d'ouverture en chargerait 30.
PERSPECTIVE_SOURCES_CAP = 3


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
        coverage_count=topic.coverage_count,
        coverage_sources=topic.coverage_sources,
        source_count=topic.source_count,
        perspective_sources=(topic.perspective_sources or [])[:PERSPECTIVE_SOURCES_CAP],
        divergence_level=topic.divergence_level,
        rank=rank,
        is_read=article.is_read,
        is_saved=article.is_saved,
        is_liked=article.is_liked,
        is_dismissed=article.is_dismissed,
        read_at=article.read_at,
        time_spent_seconds=article.time_spent_seconds,
        completed_at=article.completed_at,
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
    no-prefs (le scorer dégénère en importance éditoriale ⊕ pillar_score,
    tie-break rang).
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
        coverage_count=1,
        coverage_sources=[source.model_dump(mode="json")],
        source_count=0,
        perspective_sources=[],
        rank=rank,
        is_followed_source=True,
        is_followed_topic=bool(content.theme and content.theme in ctx.topic_weights),
        is_actu_du_jour=False,
        language=content.language,
    )


def _morning_anchor(now: datetime | None) -> datetime:
    """Début de journée Paris (minuit) en UTC — ancre « depuis ce matin ».

    Robuste au `is_stale_fallback` (où `digest.generated_at` = hier) : on borne
    toujours au minuit Paris courant, jamais à la génération du digest.
    """
    ref = (now or datetime.now(UTC)).astimezone(PARIS_TZ)
    midnight_paris = datetime.combine(ref.date(), datetime.min.time(), tzinfo=PARIS_TZ)
    return midnight_paris.astimezone(UTC)


def _score_live_candidate(
    content: Content, ctx: EssentielUserContext, now: datetime | None = None
) -> float:
    """Scoring léger d'un candidat frais (recall live), rescalé sur le mélange.

    Les candidats live n'ont pas de `pillar_score` : la perso brute reste les
    bonus déclaratifs en place (source suivie ×priority_multiplier, thème
    apprécié ×topic_weight), clampée puis mélangée via `blended_subject_score`
    avec une importance mono-source (couverture 1 ⇒ récence seule) — même
    échelle que `_score_article`. Pas de branchement moteur ici :
    `fetch_user_essentiel_context` ne charge que des prefs déclaratives
    (ScoringContext complet reporté à une PR 6-bis). Pas de read-penalty : le
    `WHERE` exclut déjà les lus. Ordonne, ne gate jamais la découverte.

    ⚠️ Signature rétro-compatible (`now` optionnel en dernier) : importée par
    `topic_alert_producer` et `source_alert_producer` en 2-arguments.
    """
    perso_raw = 0.0
    if content.source_id in ctx.followed_source_ids:
        multiplier = ctx.source_priority_multipliers.get(content.source_id, 1.0)
        perso_raw += _W_FOLLOWED_SOURCE * multiplier
    if content.theme and content.theme in ctx.topic_weights:
        perso_raw += _W_TOPIC_WEIGHT * ctx.topic_weights[content.theme]
    return blended_subject_score(1, content.published_at, None, perso_raw, now=now)


async def _fetch_live_supplements(
    db: AsyncSession,
    user_id: UUID,
    ctx: EssentielUserContext,
    *,
    is_serene: bool,
    existing: list[EssentielArticle],
    limit: int,
    digest_content_ids: set[UUID],
    morning_anchor: datetime,
    now: datetime | None = None,
    start_rank: int | None = None,
    inherit_source_counts: bool = True,
    exclude_ids: set[UUID] | None = None,
    candidate_cap: int = ESSENTIEL_SUPPLEMENT_CANDIDATE_CAP,
    window: timedelta = ESSENTIEL_TOURNEE_WINDOW,
) -> tuple[list[EssentielArticle], int]:
    """Pool live frais pour le blend « toujours actif » de l'Essentiel.

    Sources candidates = sources **suivies/favorites** (`followed_source_ids`)
    ∪ sources **riches sur un thème apprécié** (`Source.coverage_themes`
    recoupant `topic_weights` — couverture data-driven 90 j, jamais un input de
    scoring), moins les sources mutées. `coverage_themes = NULL` (volume
    insuffisant) exclut naturellement la source ⇒ gate « thème riche en
    contenu ». Fenêtre de fraîcheur commune (`ESSENTIEL_TOURNEE_WINDOW`), en
    excluant :
    - contenus lus (`status == CONSUMED`) ou masqués (`is_hidden`),
    - sources mutées et sujets mutés (`muted_topic_slugs`),
    - doublons de contenu/source (cap 2/source)/sujet déjà présents,
    - en mode serein, tout `Content.is_serene != True`,
    - podcasts/vidéos/Reddit/bulletins (mêmes critères que le digest).

    Retourne `(supplements, new_since_morning)` : les articles frais retenus
    (au plus `limit`, scorés desc) et le compte de candidats frais publiés
    depuis `morning_anchor` et absents du digest (borné plus haut au cap).

    `start_rank` force le rang du premier article retenu. Par défaut il suit
    `existing` (blend du digest : les compléments prolongent les 5 slots).
    `fetch_essentiel_more` le force à 1 : ses `existing` ne sont là que pour la
    dédup (ils ne sont pas servis), et le rang n'y a aucune signification.

    `inherit_source_counts=False` découple le cap par source d'`existing` : le
    cap ne s'applique alors qu'**entre les articles servis**. Même raison —
    `fetch_essentiel_more` passe en `existing` tout ce que le client détient
    déjà (jusqu'à une dizaine d'articles) ; leur faire consommer le quota de
    leur source ferait rendre une liste vide dès que le client tient 1 article
    par source du pool, et « Plus d'articles ? » n'aurait plus jamais rien à
    servir. La dédup content_id et titre, elle, reste héritée.

    `exclude_ids` est poussé **dans le SQL, avant le `LIMIT`** (Story 33.4).
    C'était la correction la plus rentable du lot : les ids déjà détenus par le
    client étaient filtrés en Python *après* le cap de candidats, donc ils
    consommaient des slots du top-N et la fenêtre utile rétrécissait à chaque
    tour — au bout de deux élargissements, « Plus d'articles ? » ne trouvait
    plus rien alors que la base en avait. `existing` reste passé séparément :
    lui alimente la dédup titre/source, pas le `WHERE`.

    `candidate_cap` et `window` sont paramétrables pour la même raison :
    `fetch_essentiel_more` a besoin d'un pool plus large
    (`ESSENTIEL_MORE_CANDIDATE_CAP`) et d'une fenêtre élargissable par paliers
    (`ESSENTIEL_MORE_WINDOW_STEPS`), là où le blend du digest reste sur les
    24 h et le top-30 qui lui suffisent.
    """
    # Sources candidates = suivies ∪ riches-sur-thème-apprécié, poussées dans le
    # JOIN pour éviter un aller-retour séparé (le blend tourne à chaque requête).
    # `coverage_themes` recoupant les thèmes appréciés découvre les sources
    # riches ; NULL n'overlap jamais ⇒ gate « thème riche en contenu ».
    followed = ctx.followed_source_ids
    liked_slugs = set(ctx.topic_weights)
    source_predicates = []
    if followed:
        source_predicates.append(Source.id.in_(list(followed)))
    if liked_slugs:
        source_predicates.append(Source.coverage_themes.overlap(list(liked_slugs)))
    if not source_predicates:
        return [], 0

    cutoff = (now or datetime.now(UTC)) - window
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
        .where(or_(*source_predicates))
        .where(Content.published_at >= cutoff)
        .where(Content.content_type == ContentType.ARTICLE)
        .where(~already_read_or_hidden)
        .where(Source.is_active.is_(True))
        .order_by(Content.published_at.desc())
        .limit(candidate_cap)
    )
    if ctx.muted_source_ids:
        query = query.where(Source.id.notin_(list(ctx.muted_source_ids)))
    if is_serene:
        query = query.where(Content.is_serene.is_(True))
    # **Avant** le `LIMIT` (cf. docstring) : un id déjà détenu par le client ne
    # doit pas consommer un slot du pool de candidats.
    if exclude_ids:
        query = query.where(Content.id.notin_(list(exclude_ids)))

    candidates = list((await db.execute(query)).scalars().all())
    if not candidates:
        return [], 0

    # Delta « N nouveaux depuis ce matin » : candidats frais (publiés depuis le
    # minuit Paris) et absents du digest du jour. Indépendant de l'ordre → calculé
    # avant le tri, qui n'est utile que pour la sélection des slots.
    new_since_morning = sum(
        1
        for c in candidates
        if c.published_at >= morning_anchor and c.id not in digest_content_ids
    )

    if limit <= 0:
        return [], new_since_morning

    # Scoring léger : ordonne les candidats par composite (source suivie / thème
    # apprécié), tie-break `published_at` desc — cohérent avec le reste du feed.
    candidates.sort(
        key=lambda c: (_score_live_candidate(c, ctx, now=now), c.published_at),
        reverse=True,
    )

    # Dédup contre les articles déjà retenus (ancre non-lus) : content_id, cap
    # source, similarité de titre — mêmes garde-fous que `_pick_transversal_articles`.
    seen_content_ids = {a.content_id for a in existing}
    source_count: dict[UUID, int] = {}
    if inherit_source_counts:
        for article in existing:
            source_count[article.source.id] = source_count.get(article.source.id, 0) + 1
    picked_title_tokens = [normalize_title(a.title) for a in existing if a.title]

    supplements: list[EssentielArticle] = []
    rank = start_rank if start_rank is not None else len(existing) + 1

    def _fill(cap: int) -> None:
        nonlocal rank
        for content in candidates:
            if len(supplements) >= limit:
                return
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
            if source_count.get(source.id, 0) >= cap:
                continue
            tokens = normalize_title(content.title)
            if tokens and any(
                jaccard_similarity(tokens, prev)
                >= ScoringWeights.TOPIC_CLUSTER_THRESHOLD
                for prev in picked_title_tokens
                if prev
            ):
                continue
            supplements.append(_content_to_essentiel_article(content, rank, ctx))
            seen_content_ids.add(content.id)
            source_count[source.id] = source_count.get(source.id, 0) + 1
            picked_title_tokens.append(tokens)
            rank += 1

    # 1re passe cap 1/source (diversité) ; fallback cap 2 pour compléter les
    # slots libres si le pool de sources distinctes est trop pauvre.
    _fill(ESSENTIEL_MAX_PER_SOURCE)
    if len(supplements) < limit and ESSENTIEL_MAX_PER_SOURCE < _MAX_PER_SOURCE_FALLBACK:
        _fill(_MAX_PER_SOURCE_FALLBACK)

    return supplements, new_since_morning


async def fetch_essentiel_more(
    db: AsyncSession,
    user_id: UUID,
    ctx: EssentielUserContext,
    *,
    is_serene: bool,
    exclude_ids: set[UUID],
    limit: int,
    now: datetime | None = None,
) -> list[EssentielArticle]:
    """`limit` recommandations Essentiel **inédites** — Story 33.3, élargie 33.4.

    Sert « Plus d'articles ? » **et** le prefetch automatique de la pile de tri :
    depuis la 33.4, l'objectif de l'utilisateur est un nombre d'articles à
    *garder*, donc la pile doit pouvoir continuer à proposer tant que la cible
    n'est pas atteinte. C'est cette fonction qui la nourrit.

    Aucun nouveau moteur : c'est exactement le pool live du blend « Essentiel
    vivant » ([_fetch_live_supplements]) — sources suivies ∪ sources riches sur
    un thème apprécié, exclusion des lus / masqués / mutés, cap par source,
    dédup de titre. Trois réglages seulement le distinguent du blend digest :

    - les exclusions partent **dans le SQL**, avant le `LIMIT` ;
    - un cap de candidats dédié (`ESSENTIEL_MORE_CANDIDATE_CAP`) ;
    - une fenêtre en paliers (`ESSENTIEL_MORE_WINDOW_STEPS`), qui s'arrête dès
      que `limit` articles sont tenus.

    `exclude_ids` = tout ce que le client porte déjà (slate ∪ décidés ∪ pool
    local). Les contenus correspondants sont aussi hydratés en `EssentielArticle`
    pour alimenter la dédup **titre et source** du moteur : sans ça, on
    renverrait le même papier vu d'une autre rédaction juste après que
    l'utilisateur l'a écarté.

    Liste vide = pas d'inédit (pool épuisé, ou utilisateur sans source suivie ni
    thème apprécié) : c'est un état normal, jamais une erreur. Read-only.
    """
    if limit <= 0:
        return []

    already: list[EssentielArticle] = []
    if exclude_ids:
        rows = await db.execute(
            select(Content)
            .options(selectinload(Content.source))
            .where(Content.id.in_(list(exclude_ids)))
        )
        already = [
            # Le rang n'a aucun sens ici (ces articles ne sont pas servis) :
            # `_fetch_live_supplements` ne lit que `content_id`, `source.id` et
            # `title` de cette liste.
            _content_to_essentiel_article(content, 1, ctx)
            for content in rows.scalars().all()
        ]

    morning_anchor = _morning_anchor(now)
    supplements: list[EssentielArticle] = []
    for window in ESSENTIEL_MORE_WINDOW_STEPS:
        supplements, _ = await _fetch_live_supplements(
            db,
            user_id,
            ctx,
            is_serene=is_serene,
            existing=already,
            limit=limit,
            digest_content_ids=set(exclude_ids),
            morning_anchor=morning_anchor,
            now=now,
            # Les articles servis sont rangés 1..limit pour eux-mêmes : le rang
            # d'`already` n'est pas une position réelle.
            start_rank=1,
            # `already` sert à la dédup, pas au quota : cf. la note du paramètre.
            inherit_source_counts=False,
            exclude_ids=exclude_ids,
            candidate_cap=ESSENTIEL_MORE_CANDIDATE_CAP,
            window=window,
        )
        # Chaque palier **réinclut** le précédent (la fenêtre s'élargit, elle ne
        # glisse pas) : le lot obtenu est complet, on ne cumule pas.
        if len(supplements) >= limit:
            break
    # Filet : un `exclude_id` que la DB ne connaît plus (contenu purgé) n'est pas
    # dans `already`, donc pas dans la dédup content_id du moteur.
    return [a for a in supplements if a.content_id not in exclude_ids]


def _is_within_read_grace(article: EssentielArticle, now: datetime | None) -> bool:
    """True si l'article a été lu il y a moins de `ESSENTIEL_READ_EVICTION_GRACE`.

    Protège un article tout juste lu de l'éviction "Essentiel vivant" le temps
    que l'utilisateur voie la coche persister sur un cold-start proche.
    """
    if not article.is_read or article.read_at is None:
        return False
    reference = now or datetime.now(UTC)
    read_at = article.read_at
    if read_at.tzinfo is None:
        read_at = read_at.replace(tzinfo=UTC)
    return reference - read_at < ESSENTIEL_READ_EVICTION_GRACE


async def build_essentiel_response_with_supplements(
    db: AsyncSession,
    user_id: UUID,
    digest: DigestResponse,
    *,
    user_context: EssentielUserContext,
    is_serene: bool,
    now: datetime | None = None,
) -> EssentielResponse:
    """Construit l'Essentiel « vivant » : ancre éditoriale + blend live.

    Contrairement à l'ancien comportement (complétion seulement si < 3), le
    blend est **toujours actif** pour livrer une surface dynamique au fil de la
    journée, tout en préservant l'ancre éditoriale et le cap 5 :

    1. Projection digest → jusqu'à 5 articles rankés + read-pénalisés.
    2. Partition en **non-lus** (ancre stable, ordre digest ; inclut les lus
       tout juste marqués, en grâce) et **lus** (évictables, hors grâce).
    3. Pool live frais (sources suivies ∪ thèmes appréciés riches), scoré, pour
       remplir les slots libérés à mesure que l'utilisateur lit.
    4. Ordre final ≤ 5 : non-lus → live (score desc) → lus en dernier recours.
    5. Delta « N nouveaux depuis ce matin » borné (`_ESSENTIEL_DELTA_CAP`).

    Le router décide ensuite du 202 ``preparing`` si le total reste < 3.
    """
    response = build_essentiel_response(digest, user_context=user_context, now=now)

    non_read: list[EssentielArticle] = []
    read: list[EssentielArticle] = []
    for article in response.articles:
        if not article.is_read or _is_within_read_grace(article, now):
            non_read.append(article)
        else:
            read.append(article)
    digest_content_ids = {a.content_id for a in response.articles}
    morning_anchor = _morning_anchor(now)

    live, new_since_morning = await _fetch_live_supplements(
        db,
        user_id,
        user_context,
        is_serene=is_serene,
        existing=non_read,
        limit=ESSENTIEL_MAX_ARTICLES - len(non_read),
        digest_content_ids=digest_content_ids,
        morning_anchor=morning_anchor,
        now=now,
    )

    # Ordre final : ancre non-lus (ordre digest) → frais (score desc) → lus du
    # digest en dernier recours si on n'atteint pas encore le cap.
    merged: list[EssentielArticle] = list(non_read) + list(live)
    if len(merged) < ESSENTIEL_MAX_ARTICLES:
        seen = {a.content_id for a in merged}
        for article in read:
            if len(merged) >= ESSENTIEL_MAX_ARTICLES:
                break
            if article.content_id in seen:
                continue
            merged.append(article)
            seen.add(article.content_id)
    merged = merged[:ESSENTIEL_MAX_ARTICLES]
    reranked = [
        article.model_copy(update={"rank": i + 1}) for i, article in enumerate(merged)
    ]

    delta = min(_ESSENTIEL_DELTA_CAP, new_since_morning)
    if live:
        logger.info(
            "essentiel_supplemented digest_count=%d live=%d final_count=%d "
            "new_since_morning=%d",
            len(response.articles),
            len(live),
            len(reranked),
            delta,
        )
    return response.model_copy(
        update={"articles": reranked, "new_since_this_morning": delta}
    )
