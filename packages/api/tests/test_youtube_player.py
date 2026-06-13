"""Tests pour la route player YouTube (page IFrame servie depuis notre origine)."""

import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app


@pytest.mark.asyncio
async def test_player_returns_html_with_video_id():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        resp = await ac.get("/api/youtube/player", params={"v": "dQw4w9WgXcQ"})

    assert resp.status_code == 200
    assert resp.headers["content-type"].startswith("text/html")
    assert resp.headers.get("cache-control") == "public, max-age=3600"
    # Le video_id est injecté et l'API IFrame officielle est chargée.
    assert "dQw4w9WgXcQ" in resp.text
    assert "https://www.youtube.com/iframe_api" in resp.text
    assert "onYouTubeIframeAPIReady" in resp.text


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "bad_id",
    [
        "short",  # trop court (len != 11 → rejeté par Query min_length)
        "twelvechars1",  # trop long (len != 11 → rejeté par Query max_length)
    ],
)
async def test_player_rejects_wrong_length(bad_id: str):
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        resp = await ac.get("/api/youtube/player", params={"v": bad_id})

    assert resp.status_code == 422  # FastAPI Query validation


@pytest.mark.asyncio
async def test_player_rejects_injection_chars():
    # 11 caractères mais avec des chars hors [A-Za-z0-9_-] → 400 (pas d'injection).
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        resp = await ac.get("/api/youtube/player", params={"v": "abc<script>"})

    assert resp.status_code == 400
    assert resp.json()["detail"] == "invalid_video_id"
