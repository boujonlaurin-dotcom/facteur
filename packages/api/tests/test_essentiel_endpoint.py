"""Tests pour `GET /api/essentiel` (Story 9.1).

L'endpoint projette la `DigestResponse` du jour (ou son fallback) en 5
articles transversaux pour la carte hi-fi mobile.

Pour rester rapide et déterministe, on mocke `read_digest_or_fallback` ; le
chemin de fallback lui-même est déjà couvert par `test_digest_readonly_hotpath.py`.
"""

from __future__ import annotations

from datetime import UTC, date, datetime
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
    *, rank: int, title: str = "Article", source_name: str = "Le Monde"
) -> DigestTopicArticle:
    return DigestTopicArticle(
        content_id=uuid4(),
        title=title,
        url=f"https://example.com/{title.lower().replace(' ', '-')}",
        published_at=datetime.now(UTC),
        source=_make_source(source_name),
        rank=rank,
        reason="Test",
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
