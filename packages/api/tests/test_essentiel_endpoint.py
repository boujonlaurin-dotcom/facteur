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
from app.models.enums import ContentType
from app.schemas.content import SourceMini
from app.schemas.digest import DigestResponse, DigestTopic, DigestTopicArticle
from app.services.essentiel_service import (
    _W_TRENDING,
    _W_UNE,
    ESSENTIEL_MAX_ARTICLES,
    EssentielUserContext,
    _perspective_score,
    _score_article,
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
    badge: str | None = None,
    is_read: bool = False,
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
        badge=badge,
        is_read=is_read,
    )


def _make_topic(
    *,
    rank: int,
    label: str = "Tech",
    theme: str | None = "technologie",
    perspective_count: int = 3,
    n_articles: int = 1,
    is_trending: bool = False,
    is_une: bool = False,
) -> DigestTopic:
    return DigestTopic(
        topic_id=f"topic-{rank}",
        label=label,
        rank=rank,
        reason="Test",
        theme=theme,
        perspective_count=perspective_count,
        is_trending=is_trending,
        is_une=is_une,
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


def test_build_essentiel_one_subject_per_topic_no_backfill():
    """Invariant transversal : un topic (= 1 sujet) ne fournit qu'1 article.

    Régression bug 2026-05-31 : un topic « revue de presse » multi-articles
    (ex: météore couvert par 3 médias) remplissait l'Essentiel avec le même
    sujet 3×. On préfère désormais rendre < 5 articles plutôt que dupliquer.
    """
    topics = [_make_topic(rank=1, label="Tech", n_articles=5)]
    digest = _make_digest(topics)

    response = build_essentiel_response(digest)

    # 1 seul sujet disponible → 1 seul article (pas de remplissage intra-topic).
    assert len(response.articles) == 1
    assert response.articles[0].section_label == "Tech"


def test_build_essentiel_handles_sparse_digest():
    topics = [_make_topic(rank=1, label="Tech", n_articles=2)]
    digest = _make_digest(topics)

    response = build_essentiel_response(digest)

    # Un topic = un sujet → 1 article, jamais 2 angles du même sujet.
    assert len(response.articles) == 1
    assert response.articles[0].rank == 1


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

    # Topic vide ignoré ; le topic Tech ne contribue qu'1 article (1 sujet).
    assert len(response.articles) == 1
    assert all(a.section_label == "Tech" for a in response.articles)


def test_build_essentiel_dedup_same_subject_multi_source_topic():
    """Bug 1 reproduction : 1 topic multi-sources sur le MÊME sujet (météore
    couvert par 3 médias distincts) ne doit apparaître qu'une fois."""
    src_home = _make_source("Home Fil actu")
    src_ouest = _make_source("Ouest-France")
    src_figaro = _make_source("Le Figaro")
    meteor = _make_topic(rank=1, label="Météore", theme="science", n_articles=0)
    meteor.articles = [
        _make_article(
            rank=1,
            title='"300 tonnes de TNT": un météore explose au-dessus des États-Unis',
            source=src_home,
            badge="actu",
        ),
        _make_article(
            rank=2,
            title="Un météore explose au-dessus des États-Unis et se fait entendre",
            source=src_ouest,
        ),
        _make_article(
            rank=3,
            title="Un météore explose au-dessus des États-Unis, détonations",
            source=src_figaro,
        ),
    ]
    other = _make_topic(rank=2, label="Économie", theme="economy", n_articles=1)
    digest = _make_digest([meteor, other])

    response = build_essentiel_response(digest)

    # Le sujet météore (même topic, 3 sources) n'apparaît qu'une fois.
    meteor_articles = [a for a in response.articles if "météore" in a.title.lower()]
    assert len(meteor_articles) == 1


def test_build_essentiel_dedup_near_duplicate_titles_across_topics():
    """Filet anti-doublon de titre : deux topics distincts couvrant le même
    événement (titres quasi-identiques) ne produisent qu'un seul article."""
    split_a = _make_topic(rank=1, label="Élection A", theme="politics", n_articles=0)
    split_a.articles = [
        _make_article(
            rank=1,
            title="Élection présidentielle : large victoire du candidat sortant annoncée",
            source=_make_source("Le Monde"),
        )
    ]
    split_b = _make_topic(rank=2, label="Élection B", theme="politics", n_articles=0)
    split_b.articles = [
        _make_article(
            rank=1,
            title="Élection présidentielle : victoire large du candidat sortant",
            source=_make_source("Le Figaro"),
        )
    ]
    digest = _make_digest([split_a, split_b])

    response = build_essentiel_response(digest)

    assert len(response.articles) == 1


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

    with (
        patch(
            "app.routers.essentiel.read_digest_or_fallback",
            new=AsyncMock(return_value=digest),
        ),
        patch(
            "app.routers.essentiel.fetch_user_essentiel_context",
            new=AsyncMock(return_value=EssentielUserContext()),
        ),
        patch(
            "app.routers.essentiel.DigestService.get_user_serein_enabled",
            new=AsyncMock(return_value=False),
        ),
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
    with (
        patch(
            "app.routers.essentiel.read_digest_or_fallback",
            new=AsyncMock(return_value=None),
        ),
        patch(
            "app.routers.essentiel.DigestService.get_user_serein_enabled",
            new=AsyncMock(return_value=False),
        ),
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

    with (
        patch(
            "app.routers.essentiel.read_digest_or_fallback",
            new=AsyncMock(return_value=digest),
        ),
        patch(
            "app.routers.essentiel.fetch_user_essentiel_context",
            new=AsyncMock(return_value=EssentielUserContext()),
        ),
        patch(
            "app.routers.essentiel.DigestService.get_user_serein_enabled",
            new=AsyncMock(return_value=False),
        ),
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
                _make_article(rank=1, title="P-1", source=other_source),
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
                _make_article(rank=1, title="C-1", source=followed_source),
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
                _make_article(rank=1, title="S-1", source=followed, published_at=stale),
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
            articles=[_make_article(rank=1, title="C-1", source=followed_source)],
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
        ) as mock_read,
        patch(
            "app.routers.essentiel.fetch_user_essentiel_context",
            new=AsyncMock(return_value=fake_ctx),
        ),
        patch(
            "app.routers.essentiel.DigestService.get_user_serein_enabled",
            new=AsyncMock(return_value=False),
        ),
    ):
        async with _client() as client:
            resp = await client.get("/api/essentiel")

    assert resp.status_code == 200
    body = resp.json()
    assert body["articles"][0]["source"]["name"] == "Mediapart"
    assert body["articles"][0]["rank"] == 1
    assert mock_read.await_args.kwargs["is_serene"] is False


@pytest.mark.asyncio
async def test_get_essentiel_serein_user_fetches_serein_digest(
    auth_override: UUID,
):
    """serein_enabled=True propagates is_serene=True to read_digest_or_fallback."""
    topics = [_make_topic(rank=1, label="Tech", n_articles=3)]
    digest = _make_digest(topics)

    with (
        patch(
            "app.routers.essentiel.read_digest_or_fallback",
            new=AsyncMock(return_value=digest),
        ) as mock_read,
        patch(
            "app.routers.essentiel.fetch_user_essentiel_context",
            new=AsyncMock(return_value=EssentielUserContext()),
        ),
        patch(
            "app.routers.essentiel.DigestService.get_user_serein_enabled",
            new=AsyncMock(return_value=True),
        ),
    ):
        async with _client() as client:
            resp = await client.get("/api/essentiel")

    assert resp.status_code == 200
    assert mock_read.await_args.kwargs["is_serene"] is True


# ─── Story 9.4 — Durcissement des filtres ────────────────────────────────


def _src(
    name: str = "Le Monde",
    *,
    type_: str = "article",
    theme: str | None = None,
) -> SourceMini:
    return SourceMini(
        id=uuid4(),
        name=name,
        logo_url=None,
        type=type_,
        theme=theme,
    )


def _art(
    *,
    title: str = "Article",
    source: SourceMini | None = None,
    content_type: ContentType = ContentType.ARTICLE,
    topics: list[str] | None = None,
    rank: int = 1,
) -> DigestTopicArticle:
    return DigestTopicArticle(
        content_id=uuid4(),
        title=title,
        url=f"https://example.com/{title.lower().replace(' ', '-')[:30]}",
        published_at=datetime.now(UTC),
        source=source or _src(),
        rank=rank,
        reason="Test",
        content_type=content_type,
        topics=topics or [],
    )


def _topic(
    label: str,
    articles: list[DigestTopicArticle],
    *,
    theme: str | None = None,
    is_trending: bool = False,
    is_une: bool = False,
    perspective_count: int = 2,
    rank: int = 1,
) -> DigestTopic:
    return DigestTopic(
        topic_id=f"t-{label.lower()}",
        label=label,
        rank=rank,
        reason="Test",
        theme=theme,
        is_trending=is_trending,
        is_une=is_une,
        perspective_count=perspective_count,
        articles=articles,
    )


def test_sport_relegated_to_slot_5_when_pool_has_4_non_sport():
    """Sport doit aboutir en slot 5+ s'il y a 4 non-sport disponibles."""
    sport_src = _src("Ouest-France", theme="sport")
    sport_art = _art(
        title="Trophées UNFP. Dembélé meilleur joueur de Ligue 1",
        source=sport_src,
        topics=["sport"],
    )
    topics = [
        _topic(
            "Sport",
            [sport_art],
            theme="sport",
            is_trending=True,
            perspective_count=4,
            rank=1,
        ),
        _topic("Politique", [_art(title="P1")], theme="politique", rank=2),
        _topic("Climat", [_art(title="C1")], theme="ecologie", rank=3),
        _topic("Tech", [_art(title="T1")], theme="tech", rank=4),
        _topic("Culture", [_art(title="Cul1")], theme="culture", rank=5),
    ]
    digest = _make_digest(topics)

    response = build_essentiel_response(digest)

    assert len(response.articles) == 5
    # Sport doit être en rank 5 (dernier).
    assert response.articles[-1].section_label == "Sport"
    # Aucun article sport en rank 1-4.
    for art in response.articles[:4]:
        assert art.section_label != "Sport"


def test_sport_excluded_when_pool_under_4_non_sport():
    """Si le pool non-sport < 4 articles, le sport est exclu (pas remonté en slot 4)."""
    sport_src = _src("Ouest-France", theme="sport")
    sport_art = _art(title="F1 GP Canada", source=sport_src, topics=["sport"])
    topics = [
        _topic(
            "Sport",
            [sport_art],
            theme="sport",
            is_trending=True,
            perspective_count=5,
            rank=1,
        ),
        _topic("Politique", [_art(title="P1")], theme="politique", rank=2),
        _topic("Climat", [_art(title="C1")], theme="ecologie", rank=3),
    ]
    digest = _make_digest(topics)

    response = build_essentiel_response(digest)

    # On a 2 non-sport (< 4 = min) → sport exclu, résultat = 2 articles.
    assert len(response.articles) == 2
    assert all(a.section_label != "Sport" for a in response.articles)


def test_sport_detected_via_content_topic_even_if_source_theme_is_society():
    """Régression TrashTalk : source.theme="society" mais topics=["sport"]."""
    trashtalk = _src("TrashTalk", theme="society")
    nba_art = _art(
        title="Victor Wembanyama, 33 points et un impact majeur",
        source=trashtalk,
        topics=["sport"],  # ML a bien classifié "sport"
    )
    topics = [
        _topic(
            "NBA",
            [nba_art],
            theme="sport",
            is_trending=True,
            perspective_count=2,
            rank=1,
        ),
        _topic("Politique", [_art(title="P1")], theme="politique", rank=2),
        _topic("Climat", [_art(title="C1")], theme="ecologie", rank=3),
        _topic("Tech", [_art(title="T1")], theme="tech", rank=4),
        _topic("Culture", [_art(title="Cul1")], theme="culture", rank=5),
    ]
    digest = _make_digest(topics)

    response = build_essentiel_response(digest)

    # NBA (TrashTalk) doit être en rank 5, pas en lead.
    assert response.articles[-1].section_label == "NBA"


def test_sport_detected_via_title_keyword_only():
    """Sport détecté via keyword titre même sans theme/topics."""
    src = _src("Europe 1", theme="society")
    sport_art = _art(
        title="Play-offs NBA : le Thunder répond aux Spurs de Wembanyama",
        source=src,
        topics=[],  # pas de ML
    )
    topics = [
        _topic(
            "Play-offs",
            [sport_art],
            theme="society",
            is_trending=True,
            perspective_count=2,
            rank=1,
        ),
        _topic("Politique", [_art(title="P1")], theme="politique", rank=2),
        _topic("Climat", [_art(title="C1")], theme="ecologie", rank=3),
        _topic("Tech", [_art(title="T1")], theme="tech", rank=4),
        _topic("Culture", [_art(title="Cul1")], theme="culture", rank=5),
    ]
    digest = _make_digest(topics)

    response = build_essentiel_response(digest)

    assert response.articles[-1].section_label == "Play-offs"


def test_news_bulletin_journal_de_8h_excluded():
    """« JOURNAL DE 8H du lundi 25 mai 2026 » exclu même si trending."""
    france_culture = _src("France Culture", theme="culture")
    bulletin = _art(
        title="JOURNAL DE 8H du lundi 25 mai 2026",
        source=france_culture,
    )
    topics = [
        _topic(
            "Bulletin",
            [bulletin],
            theme="culture",
            is_trending=True,
            perspective_count=2,
            rank=1,
        ),
        _topic("Politique", [_art(title="P1")], theme="politique", rank=2),
        _topic("Climat", [_art(title="C1")], theme="ecologie", rank=3),
    ]
    digest = _make_digest(topics)

    response = build_essentiel_response(digest)

    titles = [a.title for a in response.articles]
    assert "JOURNAL DE 8H du lundi 25 mai 2026" not in titles
    assert len(response.articles) == 2  # Politique + Climat seulement


def test_news_bulletin_chronique_du_excluded():
    """« Avec Sciences, chronique du lundi… » (podcast court) exclu."""
    src = _src("La Science CQFD", type_="podcast", theme="science")
    chronique = _art(
        title="Avec Sciences, chronique du lundi 25 mai 2026",
        source=src,
        content_type=ContentType.PODCAST,  # doublement exclu
    )
    topics = [
        _topic("Chronique", [chronique], theme="science", perspective_count=2, rank=1),
        _topic("Politique", [_art(title="P1")], theme="politique", rank=2),
    ]
    digest = _make_digest(topics)

    response = build_essentiel_response(digest)

    assert all(
        a.title != "Avec Sciences, chronique du lundi 25 mai 2026"
        for a in response.articles
    )


def test_chronique_in_middle_of_title_not_excluded():
    """Faux-positif à éviter : « chronique » en milieu de phrase reste éligible."""
    src = _src("Mediapart")
    art = _art(
        title="Une chronique du conflit israélo-palestinien après deux ans",
        source=src,
    )
    topics = [
        _topic("MO", [art], theme="international", perspective_count=4, rank=1),
    ]
    digest = _make_digest(topics)

    response = build_essentiel_response(digest)

    # L'article doit passer (pattern ancré début, "chronique du" en milieu OK).
    assert len(response.articles) == 1
    assert "chronique du conflit" in response.articles[0].title


def test_podcast_content_type_excluded():
    """Tous les podcasts (content_type=PODCAST) sont exclus de l'Essentiel."""
    src = _src("France Culture")
    podcast = _art(
        title="Le Miocène Moyen, le passé pour raconter notre climat",
        source=src,
        content_type=ContentType.PODCAST,
    )
    topics = [
        _topic("Podcast", [podcast], theme="science", perspective_count=1, rank=1),
        _topic("Politique", [_art(title="P1")], theme="politique", rank=2),
    ]
    digest = _make_digest(topics)

    response = build_essentiel_response(digest)

    assert all(a.content_id != podcast.content_id for a in response.articles)


def test_youtube_content_type_excluded():
    """Vidéos YouTube (content_type=YOUTUBE) exclues de l'Essentiel."""
    src = _src("Hugo Décrypte", type_="youtube")
    yt = _art(
        title="Le récap du jour",
        source=src,
        content_type=ContentType.YOUTUBE,
    )
    topics = [
        _topic("YouTube", [yt], theme="news", perspective_count=2, rank=1),
        _topic("Politique", [_art(title="P1")], theme="politique", rank=2),
    ]
    digest = _make_digest(topics)

    response = build_essentiel_response(digest)

    assert all(a.content_id != yt.content_id for a in response.articles)


def test_reddit_source_excluded():
    """Posts de sources Reddit (r/france) exclus de l'Essentiel."""
    reddit = _src("r/france", type_="reddit")
    post = _art(
        title="Quatre policiers de la BAC condamnés",
        source=reddit,
    )
    topics = [
        _topic(
            "Reddit",
            [post],
            theme="society",
            is_trending=True,
            perspective_count=3,
            rank=1,
        ),
        _topic("Politique", [_art(title="P1")], theme="politique", rank=2),
    ]
    digest = _make_digest(topics)

    response = build_essentiel_response(digest)

    assert all(a.source.name != "r/france" for a in response.articles)


def test_perspective_score_log_curve():
    """Vérifie la calibration log2 du score perspectives."""
    assert _perspective_score(0) == 0.0
    assert _perspective_score(1) == 0.0
    # 12 * log2(2) = 12
    assert _perspective_score(2) == pytest.approx(12.0)
    # 12 * log2(4) = 24
    assert _perspective_score(4) == pytest.approx(24.0)
    # 12 * log2(6) ≈ 31 → capé à 30
    assert _perspective_score(6) == pytest.approx(30.0)
    assert _perspective_score(20) == pytest.approx(30.0)


def test_six_perspectives_beats_one_perspective_scoop():
    """Cas PO : sujet à 6 médias (sans signal éditorial) doit passer devant un
    scoop isolé (1 perspective), sans aucune préférence user."""
    pop_src = _src("Le Monde")
    scoop_src = _src("Mediapart")
    very_relayed = _art(
        title="Hauts responsables iraniens à Doha pour discussions",
        source=pop_src,
    )
    isolated = _art(
        title="Le Miocène moyen : passé du climat à venir",
        source=scoop_src,
    )
    topics = [
        # Scoop isolé en rank topic 1 (avantage rank), 1 perspective.
        _topic("Climat", [isolated], theme="science", perspective_count=1, rank=1),
        # Sujet relayé en rank topic 2, 6 perspectives.
        _topic(
            "MO", [very_relayed], theme="international", perspective_count=6, rank=2
        ),
    ]
    digest = _make_digest(topics)

    response = build_essentiel_response(digest)

    # Sans signal user, 6 perspectives (+30) > 1 perspective (0) +
    # rank_penalty (-0.5 vs -1.0) → MO passe devant.
    assert response.articles[0].section_label == "MO"
    assert response.articles[1].section_label == "Climat"


def test_actu_lead_slot_skips_sport_trending():
    """Un sport trending ne décroche pas le lead-slot Actu (Story 9.4)."""
    sport_src = _src("Ouest-France", theme="sport")
    sport_actu = _art(
        title="Coupe du monde 2026, finale historique",
        source=sport_src,
        topics=["sport"],
    )
    regular = _art(title="Politique-1", source=_src("Le Monde"))
    topics = [
        _topic(
            "Sport",
            [sport_actu],
            theme="sport",
            is_trending=True,
            perspective_count=5,
            rank=1,
        ),
        _topic("Politique", [regular], theme="politique", perspective_count=3, rank=2),
        _topic("Climat", [_art(title="C1")], theme="ecologie", rank=3),
        _topic("Tech", [_art(title="T1")], theme="tech", rank=4),
        _topic("Culture", [_art(title="Cul1")], theme="culture", rank=5),
    ]
    digest = _make_digest(topics)

    response = build_essentiel_response(digest)

    # Lead-slot = pas sport.
    assert response.articles[0].section_label != "Sport"
    # Sport en queue.
    assert response.articles[-1].section_label == "Sport"


# ─── Repasse 2026-05-27 — mutes appliqués + scoring is_trending découplé ───


def test_muted_theme_excludes_topic():
    """Sylvie 2026-05-25/26 : mute `international` → topic de theme
    international entièrement écarté (article Corée du Nord exclu)."""
    international = _topic(
        "International",
        [_art(title="Corée du Nord tire un projectile")],
        theme="international",
        is_trending=True,
        rank=1,
    )
    other = _topic("Société", [_art(title="Société-1")], theme="society", rank=2)
    digest = _make_digest([international, other])
    ctx = EssentielUserContext(muted_themes=frozenset({"international"}))

    response = build_essentiel_response(digest, user_context=ctx)

    labels = [a.section_label for a in response.articles]
    assert "International" not in labels
    assert labels == ["Société"]


def test_muted_source_excludes_article():
    """Article de source mutée écarté même si trending."""
    muted_src = _src("Frandroid")
    ok_src = _src("Le Monde")
    same_topic = _topic(
        "Tech",
        [
            _art(title="Article muted", source=muted_src),
            _art(title="Article ok", source=ok_src),
        ],
        theme="tech",
        is_trending=True,
        rank=1,
    )
    digest = _make_digest([same_topic])
    ctx = EssentielUserContext(muted_source_ids=frozenset({muted_src.id}))

    response = build_essentiel_response(digest, user_context=ctx)

    assert len(response.articles) == 1
    assert response.articles[0].title == "Article ok"


def test_muted_topic_slug_excludes_article():
    """Sylvie : mute `space` → article taggué `topics=["space"]` exclu."""
    src = _src("Le Monde")
    topic = _topic(
        "Sciences",
        [
            _art(title="Mission lunaire", source=src, topics=["space"]),
            _art(title="Biologie marine", source=src, topics=["biology"]),
        ],
        theme="sciences",
        rank=1,
    )
    digest = _make_digest([topic])
    ctx = EssentielUserContext(muted_topic_slugs=frozenset({"space"}))

    response = build_essentiel_response(digest, user_context=ctx)

    titles = [a.title for a in response.articles]
    assert "Mission lunaire" not in titles
    assert "Biologie marine" in titles


def test_no_mutes_no_regression():
    """Sans mutes : comportement identique au comportement historique."""
    topics = [
        _make_topic(rank=i + 1, label=f"T{i + 1}", n_articles=1) for i in range(3)
    ]
    digest = _make_digest(topics)

    response = build_essentiel_response(
        digest,
        user_context=EssentielUserContext(),
    )

    assert [a.section_label for a in response.articles] == ["T1", "T2", "T3"]


def test_muted_source_does_not_break_other_topics():
    """Régression : muter une source d'un topic ne doit pas vider les
    autres topics. Garantit que `_filter_articles_by_mutes` n'élague pas
    trop large."""
    muted = _src("Frandroid")
    ok = _src("Le Monde")
    topics = [
        _topic("Tech", [_art(title="T1", source=muted)], theme="tech", rank=1),
        _topic("Politique", [_art(title="P1", source=ok)], theme="politique", rank=2),
    ]
    digest = _make_digest(topics)
    ctx = EssentielUserContext(muted_source_ids=frozenset({muted.id}))

    response = build_essentiel_response(digest, user_context=ctx)

    labels = [a.section_label for a in response.articles]
    assert labels == ["Politique"]


def test_trending_and_une_decoupled_in_scoring():
    """Bug audit #6 : `is_une` et `is_trending` étaient lus du même champ
    JSONB → tout subject à la une recevait +70 (40+30). Après découplage,
    un subject avec `is_une=True` seul reçoit `+_W_UNE` (30) uniquement."""
    topic_une_only = _topic(
        "UneOnly",
        [_art(title="A1")],
        theme="theme-une",
        is_trending=False,
        is_une=True,
        perspective_count=1,
        rank=1,
    )
    topic_trending_only = _topic(
        "TrendingOnly",
        [_art(title="A2")],
        theme="theme-trending",
        is_trending=True,
        is_une=False,
        perspective_count=1,
        rank=2,
    )
    ctx = EssentielUserContext()

    une_score = _score_article(topic_une_only, topic_une_only.articles[0], ctx)
    trending_score = _score_article(
        topic_trending_only, topic_trending_only.articles[0], ctx
    )

    # `is_une` seul : +_W_UNE (30), `is_trending` seul : +_W_TRENDING (40).
    # Tie-break par rank pénalisé (-0.5 * 1).
    assert une_score == pytest.approx(_W_UNE - 0.5)
    assert trending_score == pytest.approx(_W_TRENDING - 0.5)
    # Le découplage doit produire des scores différents (avant le fix,
    # is_une=true et is_trending=true étaient toujours cumulés → scores égaux
    # ne se distinguaient jamais).
    assert une_score != trending_score


def test_une_and_trending_can_cumulate_when_both_set():
    """Cumul `+70` toujours possible mais légitime — quand le subject est
    à la fois à la une éditoriale (`is_une`) et couvert par ≥3 sources
    (`is_trending`)."""
    topic = _topic(
        "Both",
        [_art(title="A1")],
        theme="t",
        is_trending=True,
        is_une=True,
        perspective_count=1,
        rank=1,
    )

    score = _score_article(topic, topic.articles[0], EssentielUserContext())

    assert score == pytest.approx(_W_TRENDING + _W_UNE - 0.5)
