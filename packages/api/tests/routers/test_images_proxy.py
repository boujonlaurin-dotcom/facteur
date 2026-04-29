"""Tests for the web image proxy endpoint."""

from unittest.mock import AsyncMock, MagicMock, patch

import httpx
import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app


def _mock_response(status_code: int, content: bytes, content_type: str) -> MagicMock:
    resp = MagicMock()
    resp.status_code = status_code
    resp.content = content
    resp.headers = {"content-type": content_type}
    return resp


def _patched_client(get_return=None, get_side_effect=None):
    """Patches httpx.AsyncClient inside the router module."""
    mock_client_instance = MagicMock()
    mock_client_instance.__aenter__ = AsyncMock(return_value=mock_client_instance)
    mock_client_instance.__aexit__ = AsyncMock(return_value=False)
    if get_side_effect is not None:
        mock_client_instance.get = AsyncMock(side_effect=get_side_effect)
    else:
        mock_client_instance.get = AsyncMock(return_value=get_return)
    return patch(
        "app.routers.images.httpx.AsyncClient",
        return_value=mock_client_instance,
    )


@pytest.mark.asyncio
async def test_proxy_happy_path_returns_image_with_cors_and_cache():
    fake_png = b"\x89PNG\r\n\x1a\n" + b"\x00" * 32
    with _patched_client(get_return=_mock_response(200, fake_png, "image/png")):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            resp = await ac.get(
                "/api/images/proxy",
                params={"url": "https://cdn.example.com/a.png"},
            )
    assert resp.status_code == 200
    assert resp.headers["content-type"].startswith("image/png")
    assert resp.headers["access-control-allow-origin"] == "*"
    assert "max-age=604800" in resp.headers["cache-control"]
    assert resp.content == fake_png


@pytest.mark.asyncio
async def test_proxy_rejects_non_https_scheme():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        resp = await ac.get(
            "/api/images/proxy", params={"url": "http://insecure.example/a.png"}
        )
    assert resp.status_code == 400


@pytest.mark.asyncio
async def test_proxy_returns_404_when_upstream_unreachable():
    with _patched_client(get_side_effect=httpx.ConnectError("boom")):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            resp = await ac.get(
                "/api/images/proxy",
                params={"url": "https://cdn.example.com/a.png"},
            )
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_proxy_returns_415_when_content_type_not_image():
    with _patched_client(get_return=_mock_response(200, b"<html></html>", "text/html")):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            resp = await ac.get(
                "/api/images/proxy",
                params={"url": "https://cdn.example.com/page"},
            )
    assert resp.status_code == 415


@pytest.mark.asyncio
async def test_proxy_returns_404_when_upstream_not_200():
    with _patched_client(get_return=_mock_response(404, b"", "image/png")):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            resp = await ac.get(
                "/api/images/proxy",
                params={"url": "https://cdn.example.com/missing.png"},
            )
    assert resp.status_code == 404
