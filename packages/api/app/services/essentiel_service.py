"""Service `essentiel` — top 5 articles transversaux du jour (Story 9.1).

Strictement read-only : consomme la `DigestResponse` déjà calculée par la cron
nocturne via `read_digest_or_fallback`, et la projette en 5 articles cross-topic
pour la carte hi-fi "L'Essentiel du jour" du feed mobile.

Algorithme :
- 1 article par topic (l'article rank=1 de chaque topic, dans l'ordre des
  topics).
- Si < 5 topics distincts : round-robin sur les ranks suivants des topics déjà
  visités.
- Déduplication par `content_id`.
- Tronqué à 5 (peut être plus court si le digest est très pauvre).
"""

from uuid import UUID

from app.schemas.digest import DigestResponse, DigestTopic, DigestTopicArticle
from app.schemas.essentiel import EssentielArticle, EssentielKind, EssentielResponse

ESSENTIEL_MAX_ARTICLES = 5


def _source_letter(name: str) -> str:
    """Initiale (uppercase) de la source pour la pastille mobile."""
    for ch in name.strip():
        if ch.isalnum():
            return ch.upper()
    return "?"


def _pick_transversal_articles(
    topics: list[DigestTopic],
) -> list[tuple[DigestTopic, DigestTopicArticle]]:
    """Pioche jusqu'à 5 articles cross-topic.

    Round 1 : article `rank=1` de chaque topic (ordre des topics).
    Rounds suivants : article suivant (rank=2, puis rank=3, …) des topics déjà
    visités, dans le même ordre, jusqu'à atteindre 5 ou épuiser les articles.
    """
    sorted_topics = sorted((t for t in topics if t.articles), key=lambda t: t.rank)
    if not sorted_topics:
        return []

    seen_content_ids: set[UUID] = set()
    picked: list[tuple[DigestTopic, DigestTopicArticle]] = []

    max_rounds = max(len(t.articles) for t in sorted_topics)
    for round_idx in range(max_rounds):
        for topic in sorted_topics:
            if round_idx >= len(topic.articles):
                continue
            article = topic.articles[round_idx]
            if article.content_id in seen_content_ids:
                continue
            seen_content_ids.add(article.content_id)
            picked.append((topic, article))
            if len(picked) >= ESSENTIEL_MAX_ARTICLES:
                return picked
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


def build_essentiel_response(digest: DigestResponse) -> EssentielResponse:
    """Projette une `DigestResponse` en `EssentielResponse` (5 articles max)."""
    picks = _pick_transversal_articles(digest.topics)
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
