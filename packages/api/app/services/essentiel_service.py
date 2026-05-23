"""Service `essentiel` — top 5 articles transversaux du jour (Story 9.1).

Strictement read-only : consomme la `DigestResponse` déjà calculée par la cron
nocturne via `read_digest_or_fallback`, et la projette en 5 articles cross-topic
pour la carte hi-fi "L'Essentiel du jour" du feed mobile.

Algorithme user-aware (fix bug-essentiel-user-prefs) :
1. Charge le contexte user en read-only : sources suivies + multiplicateurs
   de priorité, topics suivis + poids (union UserInterest ∪ UserSubtopic).
2. Score chaque article candidat avec un scorer composite simple :
   - bonus source suivie (×priority_multiplier),
   - bonus topic suivi (×weight),
   - petit bonus perspective_count (transversal),
   - tie-break par rank.
3. Round "diversité" : 1 article max par topic (le mieux scoré), dans l'ordre
   des `topic.rank`, jusqu'à 5.
4. Round "remplissage" : complète par les articles restants triés par score
   décroissant si on n'a pas atteint 5.
5. Déduplication par `content_id`.

Fallback sans préférences : le scorer dégénère en `+perspective_count - rank`,
ce qui donne quasi le même résultat que l'ancien round-robin rank-driven.
"""

from dataclasses import dataclass, field
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.source import UserSource
from app.models.user import UserInterest, UserSubtopic
from app.schemas.digest import DigestResponse, DigestTopic, DigestTopicArticle
from app.schemas.essentiel import EssentielArticle, EssentielKind, EssentielResponse

ESSENTIEL_MAX_ARTICLES = 5

# Poids du scoring composite — réglés pour que chaque levier puisse l'emporter
# isolément sans qu'aucun ne phagocyte les autres. Toute modif → ajouter un
# test dans `test_essentiel_endpoint.py`.
_W_FOLLOWED_SOURCE = 100.0
_W_FOLLOWED_SOURCE_FLAG = 50.0  # bonus moindre si on n'a que le flag du digest
_W_TOPIC_WEIGHT = 50.0
_W_PERSPECTIVE = 5.0
_W_RANK_PENALTY = 0.5


@dataclass(frozen=True)
class EssentielUserContext:
    """Préférences user nécessaires pour re-ranker l'Essentiel.

    Toujours instanciable vide → fallback gracieux quand l'utilisateur n'a
    pas (encore) de prefs explicites.
    """

    followed_source_ids: frozenset[UUID] = field(default_factory=frozenset)
    source_priority_multipliers: dict[UUID, float] = field(default_factory=dict)
    topic_weights: dict[str, float] = field(default_factory=dict)


async def fetch_user_essentiel_context(
    db: AsyncSession, user_id: UUID
) -> EssentielUserContext:
    """Charge en read-only les signaux user utiles à l'Essentiel.

    Aucune écriture, aucun pipeline LLM. 2 SELECTs courts, indexés sur
    `user_id`. Sans hit (utilisateur sans prefs) : retourne un contexte vide.
    """
    # Sources suivies + multiplicateurs de priorité.
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

    # Topics suivis (slug → poids), union UserInterest ∪ UserSubtopic.
    # En cas de doublon : on garde le max — c'est cohérent avec l'esprit
    # "l'utilisateur a explicitement signalé son intérêt".
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

    return EssentielUserContext(
        followed_source_ids=followed_source_ids,
        source_priority_multipliers=source_priority_multipliers,
        topic_weights=topic_weights,
    )


def _source_letter(name: str) -> str:
    """Initiale (uppercase) de la source pour la pastille mobile."""
    for ch in name.strip():
        if ch.isalnum():
            return ch.upper()
    return "?"


def _score_article(
    topic: DigestTopic,
    article: DigestTopicArticle,
    ctx: EssentielUserContext,
) -> float:
    """Score composite user-aware d'un article candidat de l'Essentiel.

    Détails dans le module docstring. Toujours positif sauf au fallback
    no-prefs où on peut tomber légèrement négatif via le rank — c'est
    voulu (l'ordre relatif est ce qui compte).
    """
    score = 0.0

    # Bonus source : on préfère la jointure DB-fraîche (followed_source_ids).
    # Si elle est vide mais que le digest a déjà tagué `is_followed_source`
    # (cas où le digest a été généré avec un état UserSource différent), on
    # garde un bonus moindre pour rester cohérent côté UI.
    if article.source.id in ctx.followed_source_ids:
        multiplier = ctx.source_priority_multipliers.get(article.source.id, 1.0)
        score += _W_FOLLOWED_SOURCE * multiplier
    elif article.is_followed_source:
        score += _W_FOLLOWED_SOURCE_FLAG

    # Bonus topic suivi (poids utilisateur).
    if topic.theme and topic.theme in ctx.topic_weights:
        score += _W_TOPIC_WEIGHT * ctx.topic_weights[topic.theme]

    # Bonus "transversal" : un sujet couvert par plusieurs sources est
    # plus à sa place dans l'Essentiel qu'un scoop isolé.
    score += _W_PERSPECTIVE * float(topic.perspective_count or 0)

    # Tie-break : un article rank=1 reste préféré à rank=2 à signaux égaux.
    score -= _W_RANK_PENALTY * float(article.rank)

    return score


def _pick_transversal_articles(
    topics: list[DigestTopic],
    ctx: EssentielUserContext,
) -> list[tuple[DigestTopic, DigestTopicArticle]]:
    """Pioche jusqu'à 5 articles cross-topic, user-aware.

    - Round 1 (diversité) : pour chaque topic, on prend l'article au meilleur
      score (1 article max par topic), topics ordonnés d'abord par le meilleur
      score de leur meilleur candidat (desc), puis par `topic.rank` (asc)
      pour stabilité.
    - Round 2 (remplissage) : si <5, on complète avec les articles restants
      triés par score décroissant, dédupe par `content_id`.
    """
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

    # Pour chaque topic, le meilleur candidat et son score.
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

    # Round 1 : 1 article max par topic, dans l'ordre du meilleur score
    # de chaque topic (desc), tie-break `topic.rank` (asc).
    topic_bests_sorted = sorted(
        topic_bests, key=lambda tb: (-tb[2], tb[0].rank)
    )

    picked: list[tuple[DigestTopic, DigestTopicArticle]] = []
    seen_content_ids: set[UUID] = set()
    used_topics: set[str] = set()

    for topic, article, _ in topic_bests_sorted:
        if article.content_id in seen_content_ids:
            continue
        picked.append((topic, article))
        seen_content_ids.add(article.content_id)
        used_topics.add(topic.topic_id)
        if len(picked) >= ESSENTIEL_MAX_ARTICLES:
            return picked

    # Round 2 : remplir avec les meilleurs articles restants (tous topics
    # confondus), triés par score décroissant, tie-break `article.rank` (asc).
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
        if article.content_id in seen_content_ids:
            continue
        picked.append((topic, article))
        seen_content_ids.add(article.content_id)
        if len(picked) >= ESSENTIEL_MAX_ARTICLES:
            break

    return picked


def _to_essentiel_article(
    topic: DigestTopic,
    article: DigestTopicArticle,
    rank: int,
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
    )


def build_essentiel_response(
    digest: DigestResponse,
    user_context: EssentielUserContext | None = None,
) -> EssentielResponse:
    """Projette une `DigestResponse` en `EssentielResponse` (5 articles max).

    Si `user_context` est None, on utilise un contexte vide → fallback
    no-prefs (le scorer dégénère en perspective+rank, comportement proche
    du round-robin historique rank-driven).
    """
    ctx = user_context or EssentielUserContext()
    picks = _pick_transversal_articles(digest.topics, ctx)
    articles = [
        _to_essentiel_article(topic, article, rank=i + 1)
        for i, (topic, article) in enumerate(picks)
    ]
    return EssentielResponse(
        target_date=digest.target_date,
        generated_at=digest.generated_at,
        articles=articles,
        is_stale_fallback=digest.is_stale_fallback,
    )
