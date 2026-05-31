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

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.enums import ContentType, SourceType
from app.models.source import UserSource
from app.models.user import UserInterest, UserSubtopic
from app.models.user_personalization import UserPersonalization
from app.schemas.digest import DigestResponse, DigestTopic, DigestTopicArticle
from app.schemas.essentiel import EssentielArticle, EssentielKind, EssentielResponse
from app.services.language_user_filter import (
    get_hide_non_fr_pref,
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

# Fenêtre de cohérence avec la Tournée du jour : un article de l'Essentiel
# doit pouvoir apparaître aussi dans la Tournée (24h + sources suivies). Sans
# ce filtre, le digest peut surfacer des articles > 24h ou de sources curated
# non-suivies invisibles dans la Tournée → incohérence UI.
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

    Aucune écriture, aucun pipeline LLM. 2 SELECTs courts, indexés sur
    `user_id`. Sans hit (utilisateur sans prefs) : retourne un contexte vide.
    """
    src_rows = (
        await db.execute(
            select(UserSource.source_id, UserSource.priority_multiplier).where(
                UserSource.user_id == user_id
            )
        )
    ).all()
    followed_source_ids = frozenset(row.source_id for row in src_rows)
    source_priority_multipliers = {
        row.source_id: float(row.priority_multiplier or 1.0) for row in src_rows
    }

    topic_weights: dict[str, float] = {}

    interest_rows = (
        await db.execute(
            select(UserInterest.interest_slug, UserInterest.weight).where(
                UserInterest.user_id == user_id
            )
        )
    ).all()
    for row in interest_rows:
        if row.interest_slug:
            topic_weights[row.interest_slug] = max(
                topic_weights.get(row.interest_slug, 0.0), float(row.weight or 1.0)
            )

    subtopic_rows = (
        await db.execute(
            select(UserSubtopic.topic_slug, UserSubtopic.weight).where(
                UserSubtopic.user_id == user_id
            )
        )
    ).all()
    for row in subtopic_rows:
        if row.topic_slug:
            topic_weights[row.topic_slug] = max(
                topic_weights.get(row.topic_slug, 0.0), float(row.weight or 1.0)
            )

    hide_non_fr_sources = await get_hide_non_fr_pref(db, user_id)

    perso_row = (
        await db.execute(
            select(
                UserPersonalization.muted_themes,
                UserPersonalization.muted_topics,
                UserPersonalization.muted_sources,
            ).where(UserPersonalization.user_id == user_id)
        )
    ).first()
    muted_themes = frozenset(perso_row.muted_themes or ()) if perso_row else frozenset()
    muted_topic_slugs = (
        frozenset(perso_row.muted_topics or ()) if perso_row else frozenset()
    )
    muted_source_ids = (
        frozenset(perso_row.muted_sources or ()) if perso_row else frozenset()
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


def _filter_articles_by_tournee_pool(
    topics: list[DigestTopic],
    ctx: EssentielUserContext,
    *,
    now: datetime | None = None,
) -> list[DigestTopic]:
    """Garantit Essentiel ⊆ Tournée du jour.

    La Tournée requête live (24h + sources suivies) tandis qu'Essentiel lit
    un digest pré-calculé (7j ∪ sources curated) — sans ce filtre l'UI peut
    surfacer un article inaccessible ailleurs. No-op si l'utilisateur n'a
    aucune source suivie (sinon le filtre viderait tout).
    """
    if not ctx.followed_source_ids:
        return topics

    cutoff = (now or datetime.now(UTC)) - ESSENTIEL_TOURNEE_WINDOW
    filtered: list[DigestTopic] = []
    for topic in topics:
        kept = [
            a
            for a in topic.articles
            if a.source.id in ctx.followed_source_ids and a.published_at >= cutoff
        ]
        if kept:
            filtered.append(topic.model_copy(update={"articles": kept}))
    return filtered


def _pick_transversal_articles(
    topics: list[DigestTopic],
    ctx: EssentielUserContext,
) -> list[tuple[DigestTopic, DigestTopicArticle]]:
    """Pioche jusqu'à 5 articles cross-topic, user-aware.

    1. **Slot lead Actu** : si un article est Actu du jour (trending/une/badge),
       il prend la position 1 — quel que soit son score user. Le meilleur des
       Actu gagne.
    2. **Round diversité** (1 article max par topic), topics ordonnés par leur
       meilleur score (desc), tie-break `topic.rank` (asc).
    3. **Round remplissage** par score décroissant.
    4. **Diversité dure** : max `ESSENTIEL_MAX_PER_SOURCE` (=2) articles d'une
       même source à toutes les étapes.
    """
    # Mutes utilisateur (`user_personalization`) — prime sur tous les autres
    # filtres : un article muté ne doit jamais devenir le fallback Tournée.
    topics = _filter_articles_by_mutes(topics, ctx)
    topics = _filter_articles_by_language(topics, ctx)
    # Story 9.4 : exclure podcasts/youtube/reddit/bulletins en tête de pipeline
    # — ces contenus ne reflètent pas l'actualité chaude traitée par la presse.
    topics = _filter_articles_allowed(topics)

    # Cohérence Essentiel ⊆ Tournée du jour (24h + sources suivies).
    # Fallback : si le filtre vide tout le pool, on garde le pré-filtre pour
    # éviter une carte Essentiel vide ; on log une WARNING pour traçage.
    pre_filter_topics = topics
    topics = _filter_articles_by_tournee_pool(topics, ctx)
    if not any(t.articles for t in topics):
        if ctx.followed_source_ids:
            logger.warning(
                "tournee-pool filter emptied the pool — falling back to pre-filter "
                "topics (user has %d followed sources)",
                len(ctx.followed_source_ids),
            )
        topics = pre_filter_topics

    eligible_topics = [t for t in topics if t.articles]
    if not eligible_topics:
        return []

    # Score de chaque (topic, article) une seule fois.
    scored: dict[tuple[str, UUID], float] = {}
    for topic in eligible_topics:
        for article in topic.articles:
            scored[(topic.topic_id, article.content_id)] = _score_article(
                topic, article, ctx
            )

    picked: list[tuple[DigestTopic, DigestTopicArticle]] = []
    seen_content_ids: set[UUID] = set()
    used_topics: set[str] = set()
    source_count: dict[UUID, int] = {}
    picked_title_tokens: list[set[str]] = []

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
        if article.content_id in seen_content_ids:
            return False
        if source_count.get(article.source.id, 0) >= ESSENTIEL_MAX_PER_SOURCE:
            return False
        if _is_duplicate_subject(topic, article):
            return False
        picked.append((topic, article))
        seen_content_ids.add(article.content_id)
        used_topics.add(topic.topic_id)
        source_count[article.source.id] = source_count.get(article.source.id, 0) + 1
        picked_title_tokens.append(normalize_title(article.title))
        return True

    # ─── Slot lead Actu ──────────────────────────────────────────────────
    # Cherche le meilleur article Actu du jour (trending/une/badge=="actu").
    # S'il existe, on le pose en rank=1 avant tout le reste. Le sport est
    # exclu du lead-slot par construction (Story 9.4 : sport jamais < slot 5).
    actu_candidates: list[tuple[DigestTopic, DigestTopicArticle, float]] = []
    for topic in eligible_topics:
        for article in topic.articles:
            if _is_actu_du_jour(topic, article) and not _is_sport_pick(topic, article):
                actu_candidates.append(
                    (topic, article, scored[(topic.topic_id, article.content_id)])
                )
    if actu_candidates:
        actu_candidates.sort(key=lambda x: (-x[2], x[1].rank))
        lead_topic, lead_article, _ = actu_candidates[0]
        _try_pick(lead_topic, lead_article)

    # ─── Round 1 : diversité (1 article max par topic, hors lead) ────────
    def _best_for_topic(
        topic: DigestTopic,
    ) -> tuple[DigestTopicArticle, float]:
        best_article = max(
            topic.articles,
            key=lambda a: (
                scored[(topic.topic_id, a.content_id)],
                -a.rank,
            ),
        )
        return best_article, scored[(topic.topic_id, best_article.content_id)]

    topic_bests = [(t, *_best_for_topic(t)) for t in eligible_topics]
    topic_bests_sorted = sorted(topic_bests, key=lambda tb: (-tb[2], tb[0].rank))

    for topic, article, _ in topic_bests_sorted:
        if topic.topic_id in used_topics:
            continue
        _try_pick(topic, article)
        if len(picked) >= ESSENTIEL_MAX_ARTICLES:
            return _enforce_sport_slot_constraint(picked)

    # ─── Round 2 : remplissage (meilleurs articles restants) ─────────────
    remaining: list[tuple[DigestTopic, DigestTopicArticle, float]] = []
    for topic in eligible_topics:
        for article in topic.articles:
            if article.content_id in seen_content_ids:
                continue
            remaining.append(
                (topic, article, scored[(topic.topic_id, article.content_id)])
            )

    remaining.sort(key=lambda x: (-x[2], x[1].rank))

    for topic, article, _ in remaining:
        _try_pick(topic, article)
        if len(picked) >= ESSENTIEL_MAX_ARTICLES:
            break

    return _enforce_sport_slot_constraint(picked)


def _enforce_sport_slot_constraint(
    picked: list[tuple[DigestTopic, DigestTopicArticle]],
) -> list[tuple[DigestTopic, DigestTopicArticle]]:
    """Force le sport à occuper le slot ≥ 5 (Story 9.4), avec au plus 1 sport.

    Stratégie :
    - Partitionne en non-sport et sport (max ESSENTIEL_MAX_SPORT_PER_DIGEST).
    - Si on a ≥ (ESSENTIEL_SPORT_MIN_SLOT - 1) non-sport, on place le sport
      après — il aboutit en slot 5 ou plus.
    - Sinon le pool non-sport est trop petit pour placer le sport en slot 5+ :
      on l'exclut plutôt que de le remonter en slot < 5.
    """
    non_sport: list[tuple[DigestTopic, DigestTopicArticle]] = []
    sport: list[tuple[DigestTopic, DigestTopicArticle]] = []
    for topic, article in picked:
        if _is_sport_pick(topic, article):
            sport.append((topic, article))
        else:
            non_sport.append((topic, article))

    sport = sport[: ScoringWeights.ESSENTIEL_MAX_SPORT_PER_DIGEST]
    min_non_sport = ScoringWeights.ESSENTIEL_SPORT_MIN_SLOT - 1
    if len(non_sport) >= min_non_sport:
        return (non_sport + sport)[:ESSENTIEL_MAX_ARTICLES]
    return non_sport[:ESSENTIEL_MAX_ARTICLES]


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
) -> EssentielResponse:
    """Projette une `DigestResponse` en `EssentielResponse` (5 articles max).

    Si `user_context` est None, on utilise un contexte vide → fallback
    no-prefs (le scorer dégénère en actu_boost + perspective − rank).
    """
    ctx = user_context or EssentielUserContext()
    picks = _pick_transversal_articles(digest.topics, ctx)
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
