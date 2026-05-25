"""Tests pour `GET /api/essentiel` (Story 9.1).

L'endpoint projette la `DigestResponse` du jour (ou son fallback) en 5
articles transversaux pour la carte hi-fi mobile.

Pour rester rapide et déterministe, on mocke `read_digest_or_fallback` ; le
chemin de fallback lui-même est déjà couvert par `test_digest_readonly_hotpath.py`.
"""

from __future__ import annotations

from datetime import UTC, date, datetime, timedelta
from unittest.mock import AsyncMock, patch
from uuid import UUID, uuid4

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from app.dependencies import get_current_user_id
from app.main import app
from app.schemas.content import SourceMini
from app.schemas.digest import DigestResponse, DigestTopic, DigestTopicArticle
from app.services.essentiel_service import (
    ESSENTIEL_MAX_ARTICLES,
    EssentielUserContext,
    _source_letter,
    build_essentiel_response,
)


def _make_source(name: str = "Le Monde") -> SourceMini:
    return SourceMini(
        id=uuid4(),
        name=name,
        logo_url=None,
        type="rss",
        theme=None,
    )


def _make_article(
    *,
    rank: int,
    title: str = "Article",
    source_name: str = "Le Monde",
    source: SourceMini | None = None,
    is_followed_source: bool = False,
    published_at: datetime | None = None,
) -> DigestTopicArticle:
    return DigestTopicArticle(
        content_id=uuid4(),
        title=title,
        url=f"https://example.com/{title.lower().replace(' ', '-')}",
        published_at=published_at or datetime.now(UTC),
        source=source or _make_source(source_name),
        rank=rank,
        reason="Test",
        is_followed_source=is_followed_source,
    )


def _make_topic(
    *,
    rank: int,
    label: str = "Tech",
    theme: str | None = "technologie",
    perspective_count: int = 3,
    n_articles: int = 1,
) -> DigestTopic:
    return DigestTopic(
        topic_id=f"topic-{rank}",
        label=label,
        rank=rank,
        reason="Test",
        theme=theme,
        perspective_count=perspective_count,
        articles=[
            _make_article(rank=i + 1, title=f"{label} {i + 1}")
            for i in range(n_articles)
        ],
    )


def _make_digest(
    topics: list[DigestTopic], *, is_stale: bool = False
) -> DigestResponse:
    return DigestResponse(
        digest_id=uuid4(),
        user_id=uuid4(),
        target_date=date.today(),
        generated_at=datetime.now(UTC),
        format_version="topics_v1",
        items=[],
        topics=topics,
        is_stale_fallback=is_stale,
    )


# ─── Tests pure du service ────────────────────────────────────────────────


def test_source_letter_picks_first_alnum():
    assert _source_letter("Le Monde") == "L"
    assert _source_letter("  La Croix") == "L"
    assert _source_letter("42matters") == "4"
    assert _source_letter("") == "?"
    assert _source_letter("@@@") == "?"


def test_build_essentiel_picks_one_article_per_topic():
    topics = [
        _make_topic(rank=i + 1, label=f"T{i + 1}", n_articles=3) for i in range(5)
    ]
    digest = _make_digest(topics)

    response = build_essentiel_response(digest)

    assert len(response.articles) == ESSENTIEL_MAX_ARTICLES
    # Round-robin rank 1 → 1 article par topic en priorité
    for i, article in enumerate(response.articles):
        assert article.rank == i + 1
        assert article.section_label == f"T{i + 1}"


def test_build_essentiel_round_robin_when_few_topics():
    topics = [_make_topic(rank=1, label="Tech", n_articles=5)]
    digest = _make_digest(topics)

    response = build_essentiel_response(digest)

    assert len(response.articles) == ESSENTIEL_MAX_ARTICLES
    # Tous viennent du même topic, ranks 1..5 de l'essentiel.
    assert all(a.section_label == "Tech" for a in response.articles)
    seen_ids = {a.content_id for a in response.articles}
    assert len(seen_ids) == 5  # déduplication implicite OK


def test_build_essentiel_handles_sparse_digest():
    topics = [_make_topic(rank=1, label="Tech", n_articles=2)]
    digest = _make_digest(topics)

    response = build_essentiel_response(digest)

    assert len(response.articles) == 2
    assert response.articles[0].rank == 1
    assert response.articles[1].rank == 2


def test_build_essentiel_empty_when_no_topics():
    digest = _make_digest([])
    response = build_essentiel_response(digest)
    assert response.articles == []


def test_build_essentiel_skips_topics_without_articles():
    topics = [
        _make_topic(rank=1, label="Empty", n_articles=0),
        _make_topic(rank=2, label="Tech", n_articles=3),
    ]
    digest = _make_digest(topics)

    response = build_essentiel_response(digest)

    assert len(response.articles) == 3
    assert all(a.section_label == "Tech" for a in response.articles)


def test_build_essentiel_propagates_stale_flag():
    topics = [_make_topic(rank=1, label="Tech")]
    digest = _make_digest(topics, is_stale=True)

    response = build_essentiel_response(digest)

    assert response.is_stale_fallback is True


# ─── Tests endpoint (HTTP) ────────────────────────────────────────────────


@pytest_asyncio.fixture
async def auth_override():
    """Override `get_current_user_id` pour bypasser le JWT pendant le test."""
    user_id = uuid4()

    async def _fake_user() -> str:
        return str(user_id)

    app.dependency_overrides[get_current_user_id] = _fake_user
    try:
        yield user_id
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)


def _client() -> AsyncClient:
    transport = ASGITransport(app=app)
    return AsyncClient(transport=transport, base_url="http://test")


@pytest.mark.asyncio
async def test_get_essentiel_returns_5_articles(auth_override: UUID):
    topics = [
        _make_topic(rank=i + 1, label=f"T{i + 1}", n_articles=2) for i in range(5)
    ]
    digest = _make_digest(topics)

    with patch(
        "app.routers.essentiel.read_digest_or_fallback",
        new=AsyncMock(return_value=digest),
    ):
        async with _client() as client:
            resp = await client.get("/api/essentiel")

    assert resp.status_code == 200
    body = resp.json()
    assert len(body["articles"]) == 5
    assert [a["rank"] for a in body["articles"]] == [1, 2, 3, 4, 5]
    assert body["is_stale_fallback"] is False
    # `content_id` uniques (dédup OK).
    assert len({a["content_id"] for a in body["articles"]}) == 5


@pytest.mark.asyncio
async def test_get_essentiel_returns_202_when_no_digest(auth_override: UUID):
    with patch(
        "app.routers.essentiel.read_digest_or_fallback",
        new=AsyncMock(return_value=None),
    ):
        async with _client() as client:
            resp = await client.get("/api/essentiel")

    assert resp.status_code == 202
    body = resp.json()
    assert body["status"] == "preparing"


@pytest.mark.asyncio
async def test_get_essentiel_401_without_token():
    """Sans override d'auth ni token, la route doit refuser l'accès."""
    # On retire un éventuel override résiduel pour le test.
    app.dependency_overrides.pop(get_current_user_id, None)
    async with _client() as client:
        resp = await client.get("/api/essentiel")

    assert resp.status_code in (401, 403)


@pytest.mark.asyncio
async def test_get_essentiel_propagates_stale_fallback(auth_override: UUID):
    topics = [_make_topic(rank=1, label="Tech", n_articles=5)]
    digest = _make_digest(topics, is_stale=True)

    with patch(
        "app.routers.essentiel.read_digest_or_fallback",
        new=AsyncMock(return_value=digest),
    ):
        async with _client() as client:
            resp = await client.get("/api/essentiel")

    assert resp.status_code == 200
    assert resp.json()["is_stale_fallback"] is True


# ─── Tests user-aware re-ranking (bug-essentiel-user-prefs) ─────────────────


def test_followed_source_promoted_above_unfollowed_competitor():
    """Cohérence Essentiel ⊆ Tournée : la source non-suivie est filtrée."""
    followed_source = _make_source("Mediapart")
    other_source = _make_source("Le Monde")
    topics = [
        DigestTopic(
            topic_id="t1",
            label="Politique",
            rank=1,
            reason="Test",
            theme="politique",
            perspective_count=2,
            articles=[
                _make_article(
                    rank=1, title="P-1", source=other_source
                ),
            ],
        ),
        DigestTopic(
            topic_id="t2",
            label="Climat",
            rank=2,
            reason="Test",
            theme="ecologie",
            perspective_count=2,
            articles=[
                _make_article(
                    rank=1, title="C-1", source=followed_source
                ),
            ],
        ),
    ]
    digest = _make_digest(topics)
    ctx = EssentielUserContext(
        followed_source_ids=frozenset({followed_source.id}),
        source_priority_multipliers={followed_source.id: 1.0},
    )

    response = build_essentiel_response(digest, user_context=ctx)

    assert len(response.articles) == 1
    assert response.articles[0].source.id == followed_source.id
    assert response.articles[0].rank == 1


def test_user_topic_weight_promotes_lower_ranked_topic():
    """Un topic dont le `theme` est lourdement pondéré doit remonter."""
    topics = [
        DigestTopic(
            topic_id="t1",
            label="Politique",
            rank=1,
            reason="Test",
            theme="politique",
            perspective_count=2,
            articles=[_make_article(rank=1, title="P-1")],
        ),
        DigestTopic(
            topic_id="t2",
            label="Sciences",
            rank=2,
            reason="Test",
            theme="sciences",
            perspective_count=2,
            articles=[_make_article(rank=1, title="S-1")],
        ),
        DigestTopic(
            topic_id="t3",
            label="Cuisine",
            rank=3,
            reason="Test",
            theme="cuisine",
            perspective_count=2,
            articles=[_make_article(rank=1, title="C-1")],
        ),
    ]
    digest = _make_digest(topics)
    # Le user suit fortement "sciences", très peu "politique".
    ctx = EssentielUserContext(topic_weights={"sciences": 3.0})

    response = build_essentiel_response(digest, user_context=ctx)

    # "Sciences" doit passer devant "Politique" qui avait pourtant topic.rank=1.
    assert response.articles[0].section_label == "Sciences"


def test_no_prefs_falls_back_to_rank_order():
    """Sans prefs, on retombe sur un ordre quasi-identique au legacy
    (rank=1 de chaque topic, dans l'ordre des topics).
    """
    topics = [
        _make_topic(rank=i + 1, label=f"T{i + 1}", n_articles=2) for i in range(5)
    ]
    digest = _make_digest(topics)

    response = build_essentiel_response(digest, user_context=EssentielUserContext())

    assert len(response.articles) == 5
    # Tous les topics ont le même `perspective_count` (3 par défaut), donc
    # le tie-break est `topic.rank` (asc) → ordre T1..T5.
    assert [a.section_label for a in response.articles] == [
        "T1",
        "T2",
        "T3",
        "T4",
        "T5",
    ]


def test_perspective_count_breaks_ties_when_no_prefs():
    """Sans prefs, un topic avec plus de perspectives passe devant."""
    topics = [
        DigestTopic(
            topic_id="t1",
            label="Solo",
            rank=1,
            reason="Test",
            theme="politique",
            perspective_count=1,
            articles=[_make_article(rank=1, title="Solo")],
        ),
        DigestTopic(
            topic_id="t2",
            label="Multi",
            rank=2,
            reason="Test",
            theme="ecologie",
            perspective_count=5,
            articles=[_make_article(rank=1, title="Multi")],
        ),
    ]
    digest = _make_digest(topics)

    response = build_essentiel_response(digest, user_context=EssentielUserContext())

    # "Multi" a perspective_count=5 vs "Solo"=1 → +5*(5-1)=20 points
    # (-rank*0.5 ne suffit pas à compenser), donc Multi passe devant.
    assert response.articles[0].section_label == "Multi"
    assert response.articles[1].section_label == "Solo"


def test_diversity_constraint_one_article_per_topic_in_round_one():
    """Round 1 : 1 article max par topic avant qu'un seul topic remplisse."""
    # Un topic "Politique" très scoré (5 articles), un topic "Climat" plus
    # discret. Sans contrainte de diversité, les 5 slots iraient au topic
    # Politique. Avec la contrainte, on prend 1 article par topic au round 1
    # puis on remplit.
    topics = [
        _make_topic(rank=1, label="Politique", n_articles=5),
        _make_topic(rank=2, label="Climat", n_articles=1),
    ]
    digest = _make_digest(topics)

    response = build_essentiel_response(digest)

    # On doit avoir au moins 1 article de chaque topic dans les 2 premiers.
    first_two_labels = {a.section_label for a in response.articles[:2]}
    assert first_two_labels == {"Politique", "Climat"}


def test_followed_source_flag_fallback_when_db_set_empty():
    """Si `followed_source_ids` est vide mais le digest a déjà flaggé
    `is_followed_source`, on garde un bonus moindre."""
    s_followed = _make_source("Mediapart")
    s_other = _make_source("Le Monde")
    topics = [
        DigestTopic(
            topic_id="t1",
            label="Topic A",
            rank=1,
            reason="Test",
            theme="t1",
            perspective_count=2,
            articles=[_make_article(rank=1, title="A-1", source=s_other)],
        ),
        DigestTopic(
            topic_id="t2",
            label="Topic B",
            rank=2,
            reason="Test",
            theme="t2",
            perspective_count=2,
            articles=[
                _make_article(
                    rank=1,
                    title="B-1",
                    source=s_followed,
                    is_followed_source=True,
                )
            ],
        ),
    ]
    digest = _make_digest(topics)
    # Aucun follow chargé en DB (contexte vide), mais le flag du digest doit
    # quand même promouvoir l'article B au-dessus de A (rank topic plus haut).
    ctx = EssentielUserContext()
    response = build_essentiel_response(digest, user_context=ctx)

    assert response.articles[0].source.id == s_followed.id


# ─── Filtre Tournée pool (24h + followed sources) ──────────────────────────


def test_tournee_pool_filter_drops_article_older_than_24h():
    """Un topic dont tous les articles sont > 24h doit être retiré."""
    followed = _make_source("Mediapart")
    stale = datetime.now(UTC) - timedelta(hours=30)
    topics = [
        DigestTopic(
            topic_id="t-stale",
            label="Stale",
            rank=1,
            reason="Test",
            theme="politique",
            perspective_count=2,
            articles=[
                _make_article(
                    rank=1, title="S-1", source=followed, published_at=stale
                ),
            ],
        ),
        DigestTopic(
            topic_id="t-fresh",
            label="Fresh",
            rank=2,
            reason="Test",
            theme="sciences",
            perspective_count=2,
            articles=[_make_article(rank=1, title="F-1", source=followed)],
        ),
    ]
    digest = _make_digest(topics)
    ctx = EssentielUserContext(followed_source_ids=frozenset({followed.id}))

    response = build_essentiel_response(digest, user_context=ctx)

    labels = [a.section_label for a in response.articles]
    assert "Stale" not in labels
    assert labels == ["Fresh"]


def test_tournee_pool_filter_drops_unfollowed_source():
    """Un article d'une source non-suivie est retiré du pool Essentiel."""
    followed = _make_source("Mediapart")
    curated = _make_source("Le Monde")
    topics = [
        DigestTopic(
            topic_id="t-curated",
            label="Curated",
            rank=1,
            reason="Test",
            theme="politique",
            perspective_count=2,
            articles=[_make_article(rank=1, title="C-1", source=curated)],
        ),
        DigestTopic(
            topic_id="t-followed",
            label="Followed",
            rank=2,
            reason="Test",
            theme="sciences",
            perspective_count=2,
            articles=[_make_article(rank=1, title="F-1", source=followed)],
        ),
    ]
    digest = _make_digest(topics)
    ctx = EssentielUserContext(followed_source_ids=frozenset({followed.id}))

    response = build_essentiel_response(digest, user_context=ctx)

    labels = [a.section_label for a in response.articles]
    assert labels == ["Followed"]


def test_tournee_pool_filter_keeps_mixed_topic_partially():
    """Un topic avec 1 article OK + 1 article > 24h conserve l'article OK."""
    followed = _make_source("Mediapart")
    fresh_article = _make_article(rank=1, title="OK", source=followed)
    stale_article = _make_article(
        rank=2,
        title="KO",
        source=followed,
        published_at=datetime.now(UTC) - timedelta(hours=48),
    )
    topics = [
        DigestTopic(
            topic_id="t-mixed",
            label="Mixed",
            rank=1,
            reason="Test",
            theme="politique",
            perspective_count=2,
            articles=[fresh_article, stale_article],
        ),
    ]
    digest = _make_digest(topics)
    ctx = EssentielUserContext(followed_source_ids=frozenset({followed.id}))

    response = build_essentiel_response(digest, user_context=ctx)

    assert len(response.articles) == 1
    assert response.articles[0].title == "OK"


def test_tournee_pool_filter_fallback_when_empties_pool(caplog):
    """Si le filtre vide tout, on retombe sur le pool pré-filtre + warning."""
    followed = _make_source("Mediapart")
    curated = _make_source("Le Monde")
    # Aucun article ne vient d'une source suivie → le filtre videra tout.
    topics = [
        DigestTopic(
            topic_id="t1",
            label="Only-Curated",
            rank=1,
            reason="Test",
            theme="politique",
            perspective_count=2,
            articles=[_make_article(rank=1, title="C-1", source=curated)],
        ),
    ]
    digest = _make_digest(topics)
    ctx = EssentielUserContext(followed_source_ids=frozenset({followed.id}))

    import logging

    with caplog.at_level(logging.WARNING, logger="app.services.essentiel_service"):
        response = build_essentiel_response(digest, user_context=ctx)

    # Fallback : l'article curated réapparaît plutôt que de servir une carte vide.
    assert len(response.articles) == 1
    assert response.articles[0].section_label == "Only-Curated"
    assert any("tournee-pool filter emptied" in rec.message for rec in caplog.records)


def test_tournee_pool_filter_noop_when_no_followed_sources():
    """User sans aucune source suivie : on ne filtre pas (sinon Essentiel vide)."""
    s = _make_source("Le Monde")
    topics = [
        _make_topic(rank=1, label="T1"),
    ]
    # Force toutes les sources à la même source non-suivie.
    topics[0].articles[0] = _make_article(rank=1, title="T1-1", source=s)
    digest = _make_digest(topics)
    ctx = EssentielUserContext(followed_source_ids=frozenset())

    response = build_essentiel_response(digest, user_context=ctx)

    assert len(response.articles) == 1


@pytest.mark.asyncio
async def test_get_essentiel_uses_user_context_from_router(auth_override: UUID):
    """Au niveau HTTP : si `fetch_user_essentiel_context` rapporte un follow,
    l'article correspondant doit ressortir en rank=1.
    """
    followed_source = _make_source("Mediapart")
    other_source = _make_source("Le Monde")
    topics = [
        DigestTopic(
            topic_id="t1",
            label="Politique",
            rank=1,
            reason="Test",
            theme="politique",
            perspective_count=2,
            articles=[_make_article(rank=1, title="P-1", source=other_source)],
        ),
        DigestTopic(
            topic_id="t2",
            label="Climat",
            rank=2,
            reason="Test",
            theme="ecologie",
            perspective_count=2,
            articles=[
                _make_article(rank=1, title="C-1", source=followed_source)
            ],
        ),
    ]
    digest = _make_digest(topics)

    fake_ctx = EssentielUserContext(
        followed_source_ids=frozenset({followed_source.id}),
        source_priority_multipliers={followed_source.id: 1.0},
    )

    with (
        patch(
            "app.routers.essentiel.read_digest_or_fallback",
            new=AsyncMock(return_value=digest),
        ),
        patch(
            "app.routers.essentiel.fetch_user_essentiel_context",
            new=AsyncMock(return_value=fake_ctx),
        ),
    ):
        async with _client() as client:
            resp = await client.get("/api/essentiel")

    assert resp.status_code == 200
    body = resp.json()
    assert body["articles"][0]["source"]["name"] == "Mediapart"
    assert body["articles"][0]["rank"] == 1
