"""Tests for the app_update router."""

from unittest.mock import AsyncMock, patch

import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app


@pytest.mark.asyncio
async def test_apk_redirect_returns_302_to_signed_url():
    """The /apk endpoint must 302-redirect to the GitHub-signed APK URL.

    This is the public out-of-app fallback for users stuck with a broken
    in-app updater — a single tap in the browser must land on the APK
    download, no JSON envelope.
    """
    signed_url = "https://objects.githubusercontent.com/foo.apk?token=abc"
    with patch(
        "app.routers.app_update.get_download_url",
        new=AsyncMock(return_value={"url": signed_url}),
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            resp = await ac.get("/api/app/update/apk", follow_redirects=False)

    assert resp.status_code == 302
    assert resp.headers["location"] == signed_url
