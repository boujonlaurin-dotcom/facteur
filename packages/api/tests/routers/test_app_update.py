"""Tests for the app_update router."""

from unittest.mock import AsyncMock, patch

import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app
from app.routers import app_update

# Mix de releases : prod (release-*), staging (beta-*) et iOS (ios-beta-*).
# Le canal doit faire le tri par préfixe ; l'iOS n'a pas d'.apk de toute façon.
_RELEASES = [
    {
        "draft": False,
        "tag_name": "release-20260601-1000",
        "name": "prod",
        "body": "",
        "published_at": "2026-06-01T10:00:00Z",
        "assets": [{"id": 11, "name": "Facteur-release.apk", "size": 111}],
    },
    {
        "draft": False,
        "tag_name": "beta-20260605-1200",
        "name": "staging",
        "body": "",
        "published_at": "2026-06-05T12:00:00Z",
        "assets": [{"id": 22, "name": "Facteur-beta.apk", "size": 222}],
    },
    {
        "draft": False,
        "tag_name": "ios-beta-20260605-1200",
        "name": "ios",
        "body": "",
        "published_at": "2026-06-05T12:00:00Z",
        "assets": [{"id": 33, "name": "Facteur.ipa", "size": 333}],
    },
]


class _FakeResponse:
    status_code = 200
    text = ""

    def json(self):
        return _RELEASES


class _FakeAsyncClient:
    """Stand-in async-context-manager pour httpx.AsyncClient (pas de réseau)."""

    def __init__(self, *args, **kwargs):
        pass

    async def __aenter__(self):
        return self

    async def __aexit__(self, *args):
        return False

    async def get(self, *args, **kwargs):
        return _FakeResponse()


class _FakeSettings:
    github_token = "ghp_test_token"
    github_repo = "owner/repo"


@pytest.mark.parametrize(
    "query, expected_tag, expected_asset_id",
    [
        ("?channel=beta", "beta-20260605-1200", 22),
        ("?channel=stable", "release-20260601-1000", 11),
        ("", "release-20260601-1000", 11),  # défaut = stable (rétro-compat prod)
    ],
)
@pytest.mark.asyncio
async def test_update_channel_selects_release_prefix(
    query, expected_tag, expected_asset_id
):
    """`channel` mappe sur le préfixe de tag ; absence -> stable -> release-."""
    app_update._cache.clear()
    with patch.object(app_update, "get_settings", return_value=_FakeSettings()), patch.object(
        app_update.httpx, "AsyncClient", _FakeAsyncClient
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            resp = await ac.get(f"/api/app/update{query}")

    assert resp.status_code == 200
    body = resp.json()
    assert body["tag"] == expected_tag
    assert body["apk_asset_id"] == expected_asset_id


@pytest.mark.asyncio
async def test_update_channel_cache_keyed_by_prefix():
    """Les deux canaux coexistent dans le cache sans s'écraser l'un l'autre."""
    app_update._cache.clear()
    with patch.object(app_update, "get_settings", return_value=_FakeSettings()), patch.object(
        app_update.httpx, "AsyncClient", _FakeAsyncClient
    ):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            await ac.get("/api/app/update?channel=beta")
            await ac.get("/api/app/update?channel=stable")

    assert app_update._cache["beta-"][1]["tag"] == "beta-20260605-1200"
    assert app_update._cache["release-"][1]["tag"] == "release-20260601-1000"


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
