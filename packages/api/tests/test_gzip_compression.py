"""Tests for the gzip compression middleware.

The read hot path is dominated by article text (`html_content`), serialized
twice per digest (`topics[]` + the legacy flat `items[]`) and twice again by
`/api/digest/both` (normal + serein). Measured on a realistic editorial_v1
digest, that endpoint alone shipped 934 KB uncompressed — several seconds of
transfer on mobile, on top of the ~14 `/api/feed` calls the Tournée fans out
at cold boot.

These tests pin the middleware's presence and its two boundary behaviours, so
a future middleware reshuffle cannot silently drop compression again.
Cf. docs/maintenance/maintenance-cold-boot-essentiel-perf.md.
"""

import os
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from httpx import ASGITransport, AsyncClient
from starlette.middleware.gzip import GZipMiddleware

from app.main import app


def test_gzip_middleware_is_installed() -> None:
    """The middleware stack must carry GZipMiddleware.

    Asserted structurally rather than through a response: httpx transparently
    decodes `Content-Encoding: gzip`, so a request-level check alone would
    still pass if the middleware disappeared and the body came back in clear.
    """
    assert any(m.cls is GZipMiddleware for m in app.user_middleware)


def test_gzip_sits_under_cors() -> None:
    """CORS must stay outermost so preflight responses are never compressed.

    `add_middleware` prepends, so `user_middleware[0]` is the outermost layer
    and gzip must appear strictly after it.
    """
    classes = [m.cls.__name__ for m in app.user_middleware]
    assert classes.index("CORSMiddleware") < classes.index("GZipMiddleware")


async def _fetch_openapi(accept_encoding: str):
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        return await ac.get(
            "/openapi.json", headers={"Accept-Encoding": accept_encoding}
        )


@pytest.mark.asyncio
async def test_large_response_is_compressed_over_the_wire() -> None:
    """A payload above the threshold ships gzip-encoded, and materially smaller.

    Probe is OpenAPI: large, auth-free, and representative of the JSON the read
    endpoints emit. httpx transparently *decodes* the body, so the wire size is
    read from `Content-Length` (set by the middleware on the compressed bytes)
    rather than from `resp.content`.
    """
    gzipped = await _fetch_openapi("gzip")
    plain = await _fetch_openapi("identity")

    assert gzipped.status_code == plain.status_code == 200
    assert gzipped.headers.get("content-encoding") == "gzip"

    wire = int(gzipped.headers["content-length"])
    uncompressed = int(plain.headers["content-length"])

    # Same document either way, and compression must actually pay for itself.
    assert gzipped.json() == plain.json()
    assert wire < uncompressed / 2


@pytest.mark.asyncio
async def test_image_proxy_is_not_gzipped() -> None:
    """Image bytes come back untouched even when the client accepts gzip.

    Starlette's GZipMiddleware compresses by content-*length*, not
    content-*type*, so without the router's explicit `Content-Encoding:
    identity` it would re-gzip already-compressed JPEG/PNG bytes — pure CPU
    cost on the single uvicorn worker for ~0 bytes saved.
    """
    # Incompressible payload above `minimum_size`: random bytes stand in for
    # real image data, which gzip likewise cannot shrink.
    fake_png = b"\x89PNG\r\n\x1a\n" + os.urandom(4096)

    mock_client = MagicMock()
    mock_client.__aenter__ = AsyncMock(return_value=mock_client)
    mock_client.__aexit__ = AsyncMock(return_value=False)
    upstream = MagicMock()
    upstream.status_code = 200
    upstream.content = fake_png
    upstream.headers = {"content-type": "image/png"}
    mock_client.get = AsyncMock(return_value=upstream)

    with patch("app.routers.images.httpx.AsyncClient", return_value=mock_client):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            resp = await ac.get(
                "/api/images/proxy",
                params={"url": "https://cdn.example.com/a.png"},
                headers={"Accept-Encoding": "gzip"},
            )

    assert resp.status_code == 200
    assert resp.headers.get("content-encoding") == "identity"
    assert resp.content == fake_png


@pytest.mark.asyncio
async def test_client_without_accept_encoding_still_gets_plain_json() -> None:
    """No `Accept-Encoding: gzip` ⇒ uncompressed body, unchanged semantics.

    Guards older clients (and any curl-based runbook step) against being
    handed bytes they cannot read.
    """
    resp = await _fetch_openapi("identity")

    assert resp.status_code == 200
    assert "gzip" not in resp.headers.get("content-encoding", "")
    assert resp.content.lstrip().startswith(b"{")
