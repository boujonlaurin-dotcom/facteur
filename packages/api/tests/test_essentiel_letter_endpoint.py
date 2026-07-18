"""Tests de l'attache lettre sur `GET /api/essentiel` (Story 9.6).

La chaîne digest → 5 articles est déjà couverte par `test_essentiel_endpoint` ;
ici on mocke `build_essentiel_response_with_supplements` et on teste les
chemins lettre : servie depuis le stockage, on-demand, timeout, date passée,
clé serein distincte.
"""

from __future__ import annotations

from datetime import UTC, date, datetime, timedelta
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import UUID, uuid4

import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from app.dependencies import get_current_user_id
from app.main import app
from app.schemas.content import SourceMini
from app.schemas.essentiel import EssentielArticle, EssentielResponse
from app.schemas.essentiel_letter import (
    EssentielLetter,
    LetterSegment,
    LetterSegmentType,
)
from app.utils.time import today_paris


def _article(rank: int, *, is_read: bool = False) -> EssentielArticle:
    return EssentielArticle(
        content_id=uuid4(),
        title=f"Titre {rank}",
        url=f"https://example.org/{rank}",
        published_at=datetime.now(UTC),
        source=SourceMini(
            id=uuid4(), name="Le Monde", logo_url=None, type="rss", theme=None
        ),
        source_letter="L",
        section_label=f"Sujet {rank}",
        rank=rank,
        theme="politique",
        is_read=is_read,
    )


def _response(target_date: date, *, stale: bool = False) -> EssentielResponse:
    return EssentielResponse(
        target_date=target_date,
        generated_at=datetime.now(UTC),
        articles=[_article(i + 1) for i in range(3)],
        is_stale_fallback=stale,
    )


def _letter() -> EssentielLetter:
    return EssentielLetter(
        chapo=[LetterSegment(type=LetterSegmentType.TEXT, text="Chapo.")],
        generated_at=datetime.now(UTC),
        model="mistral-small-latest",
    )


def _row(articles: list[EssentielArticle]) -> SimpleNamespace:
    return SimpleNamespace(
        letter=_letter().model_dump(mode="json"),
        articles=[a.model_dump(mode="json") for a in articles],
        generated_at=datetime.now(UTC),
    )


@pytest_asyncio.fixture
async def auth_override():
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


def _base_patches(response: EssentielResponse):
    ctx = MagicMock()
    ctx.topic_weights = {"culture": 1.0}
    ctx.followed_source_ids = frozenset()
    return (
        patch(
            "app.routers.essentiel.read_digest_or_fallback",
            new=AsyncMock(return_value=MagicMock()),
        ),
        patch(
            "app.routers.essentiel.fetch_user_essentiel_context",
            new=AsyncMock(return_value=ctx),
        ),
        patch(
            "app.routers.essentiel.build_essentiel_response_with_supplements",
            new=AsyncMock(return_value=response),
        ),
        patch(
            "app.routers.essentiel.DigestService.get_user_serein_enabled",
            new=AsyncMock(return_value=False),
        ),
    )


async def test_stored_letter_served_with_rehydrated_snapshot(auth_override: UUID):
    today = today_paris()
    snapshot = [_article(i + 1) for i in range(3)]
    rehydrated = [snapshot[0].model_copy(update={"is_read": True})] + snapshot[1:]

    p1, p2, p3, p4 = _base_patches(_response(today))
    with (
        p1,
        p2,
        p3,
        p4,
        patch(
            "app.routers.essentiel.load_letter_row",
            new=AsyncMock(return_value=_row(snapshot)),
        ),
        patch(
            "app.routers.essentiel.rehydrate_snapshot",
            new=AsyncMock(return_value=rehydrated),
        ),
        patch("app.routers.essentiel.generate_letter", new=AsyncMock()) as mock_gen,
    ):
        async with _client() as client:
            resp = await client.get("/api/essentiel")

    assert resp.status_code == 200
    body = resp.json()
    assert body["letter"] is not None
    assert body["letter"]["model"] == "mistral-small-latest"
    # Snapshot de la lettre servi (pas les picks vivants) + flags réhydratés.
    assert body["articles"][0]["content_id"] == str(snapshot[0].content_id)
    assert body["articles"][0]["is_read"] is True
    assert mock_gen.await_count == 0


async def test_on_demand_generation_stores_and_serves(auth_override: UUID):
    today = today_paris()
    response = _response(today)

    p1, p2, p3, p4 = _base_patches(response)
    with (
        p1,
        p2,
        p3,
        p4,
        patch(
            "app.routers.essentiel.load_letter_row",
            new=AsyncMock(side_effect=[None, _row(response.articles)]),
        ),
        patch(
            "app.routers.essentiel.rehydrate_snapshot",
            new=AsyncMock(return_value=response.articles),
        ),
        patch(
            "app.routers.essentiel.generate_letter",
            new=AsyncMock(return_value=_letter()),
        ) as mock_gen,
        patch("app.routers.essentiel.store_letter", new=AsyncMock()) as mock_store,
    ):
        async with _client() as client:
            resp = await client.get("/api/essentiel")

    assert resp.status_code == 200
    assert resp.json()["letter"] is not None
    assert mock_gen.await_count == 1
    assert mock_store.await_count == 1
    assert mock_store.await_args.kwargs["is_serene"] is False


async def test_on_demand_failure_returns_response_without_letter(
    auth_override: UUID,
):
    p1, p2, p3, p4 = _base_patches(_response(today_paris()))
    with (
        p1,
        p2,
        p3,
        p4,
        patch(
            "app.routers.essentiel.load_letter_row",
            new=AsyncMock(return_value=None),
        ),
        patch(
            "app.routers.essentiel.generate_letter",
            new=AsyncMock(return_value=None),
        ),
        patch("app.routers.essentiel.store_letter", new=AsyncMock()) as mock_store,
    ):
        async with _client() as client:
            resp = await client.get("/api/essentiel")

    assert resp.status_code == 200
    assert resp.json()["letter"] is None
    assert mock_store.await_count == 0


async def test_on_demand_timeout_returns_response_without_letter(
    auth_override: UUID,
):
    p1, p2, p3, p4 = _base_patches(_response(today_paris()))
    with (
        p1,
        p2,
        p3,
        p4,
        patch(
            "app.routers.essentiel.load_letter_row",
            new=AsyncMock(return_value=None),
        ),
        patch(
            "app.routers.essentiel.generate_letter",
            new=AsyncMock(side_effect=TimeoutError),
        ),
    ):
        async with _client() as client:
            resp = await client.get("/api/essentiel")

    assert resp.status_code == 200
    assert resp.json()["letter"] is None


async def test_past_date_never_generates(auth_override: UUID):
    past = today_paris() - timedelta(days=2)
    p1, p2, p3, p4 = _base_patches(_response(past))
    with (
        p1,
        p2,
        p3,
        p4,
        patch(
            "app.routers.essentiel.load_letter_row",
            new=AsyncMock(return_value=None),
        ),
        patch("app.routers.essentiel.generate_letter", new=AsyncMock()) as mock_gen,
    ):
        async with _client() as client:
            resp = await client.get("/api/essentiel", params={"target_date": str(past)})

    assert resp.status_code == 200
    assert resp.json()["letter"] is None
    assert mock_gen.await_count == 0


async def test_past_date_serves_stored_letter(auth_override: UUID):
    past = today_paris() - timedelta(days=2)
    snapshot = [_article(i + 1) for i in range(3)]
    p1, p2, p3, p4 = _base_patches(_response(past))
    with (
        p1,
        p2,
        p3,
        p4,
        patch(
            "app.routers.essentiel.load_letter_row",
            new=AsyncMock(return_value=_row(snapshot)),
        ),
        patch(
            "app.routers.essentiel.rehydrate_snapshot",
            new=AsyncMock(return_value=snapshot),
        ),
    ):
        async with _client() as client:
            resp = await client.get("/api/essentiel", params={"target_date": str(past)})

    assert resp.status_code == 200
    assert resp.json()["letter"] is not None


async def test_stale_fallback_never_generates(auth_override: UUID):
    p1, p2, p3, p4 = _base_patches(_response(today_paris(), stale=True))
    with (
        p1,
        p2,
        p3,
        p4,
        patch(
            "app.routers.essentiel.load_letter_row",
            new=AsyncMock(return_value=None),
        ),
        patch("app.routers.essentiel.generate_letter", new=AsyncMock()) as mock_gen,
    ):
        async with _client() as client:
            resp = await client.get("/api/essentiel")

    assert resp.status_code == 200
    assert resp.json()["letter"] is None
    assert mock_gen.await_count == 0


async def test_serein_uses_distinct_letter_key(auth_override: UUID):
    p1, p2, p3, p4 = _base_patches(_response(today_paris()))
    mock_load = AsyncMock(return_value=None)
    with (
        p1,
        p2,
        p3,
        p4,
        patch("app.routers.essentiel.load_letter_row", new=mock_load),
        patch(
            "app.routers.essentiel.generate_letter",
            new=AsyncMock(return_value=None),
        ) as mock_gen,
    ):
        async with _client() as client:
            resp = await client.get("/api/essentiel", params={"serein": "true"})

    assert resp.status_code == 200
    # Clé de lecture (user, date, serein=True) + variante passée au générateur.
    assert mock_load.await_args_list[0].args[3] is True
    assert mock_gen.await_args.kwargs["is_serene"] is True
