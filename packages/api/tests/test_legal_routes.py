"""Tests pour les routes légales (Privacy + CGU)."""

import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app


@pytest.mark.asyncio
@pytest.mark.parametrize("path", ["/legal/privacy", "/legal/terms"])
async def test_legal_route_returns_html(path: str):
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        resp = await ac.get(path)

    assert resp.status_code == 200
    assert resp.headers["content-type"].startswith("text/html")
    assert resp.headers.get("cache-control") == "public, max-age=3600"
    assert len(resp.text) > 100
    assert "Dernière mise à jour" in resp.text
