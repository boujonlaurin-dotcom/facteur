"""Tests for the sync-side anti-bot fallback (T3) and buffer seed (T1d)."""

from unittest.mock import AsyncMock
from uuid import uuid4

import pytest

from app.models.enums import SourceType
from app.models.source import Source
from app.services.sync_service import SyncService

_RSS = """<?xml version="1.0"?>
<rss version="2.0"><channel><title>Blog</title>
<item><title>A</title><link>https://b.ex/a</link><guid>a</guid></item>
<item><title>B</title><link>https://b.ex/b</link><guid>b</guid></item>
</channel></rss>"""


class _Resp:
    def __init__(self, status_code, text):
        self.status_code = status_code
        self.text = text

    def raise_for_status(self):
        if self.status_code >= 400:
            raise RuntimeError(f"HTTP {self.status_code}")


@pytest.mark.asyncio
async def test_fetch_feed_content_happy_path(monkeypatch):
    service = SyncService(session=None)
    service.client.get = AsyncMock(return_value=_Resp(200, _RSS))
    impersonate = AsyncMock()
    monkeypatch.setattr(
        "app.services.sync_service.fetch_with_impersonation", impersonate
    )

    content = await service._fetch_feed_content("https://b.ex/feed")
    assert content == _RSS
    impersonate.assert_not_awaited()  # never fell back on the happy path
    await service.close()


@pytest.mark.asyncio
async def test_fetch_feed_content_falls_back_to_curl_cffi_on_403(monkeypatch):
    service = SyncService(session=None)
    service.client.get = AsyncMock(return_value=_Resp(403, "blocked"))
    monkeypatch.setattr(
        "app.services.sync_service.fetch_with_impersonation",
        AsyncMock(return_value=_RSS),
    )

    content = await service._fetch_feed_content("https://b.ex/feed")
    assert content == _RSS  # recovered via curl-cffi instead of raising
    await service.close()


@pytest.mark.asyncio
async def test_fetch_feed_content_raises_when_fallback_fails(monkeypatch):
    service = SyncService(session=None)
    service.client.get = AsyncMock(return_value=_Resp(403, "blocked"))
    monkeypatch.setattr(
        "app.services.sync_service.fetch_with_impersonation",
        AsyncMock(return_value=None),
    )
    with pytest.raises(RuntimeError):
        await service._fetch_feed_content("https://b.ex/feed")
    await service.close()


@pytest.mark.asyncio
async def test_seed_recent_content_inserts_bounded_slice(monkeypatch):
    service = SyncService(session=None)
    monkeypatch.setattr(service, "_fetch_feed_content", AsyncMock(return_value=_RSS))
    saved = AsyncMock(return_value=True)
    monkeypatch.setattr(service, "_save_content", saved)

    source = Source(
        id=uuid4(),
        name="Blog",
        url="https://b.ex",
        feed_url="https://b.ex/feed",
        type=SourceType.ARTICLE,
    )
    seeded = await service.seed_recent_content(source, max_items=10)
    assert seeded == 2  # both feed entries saved
    assert saved.await_count == 2
    await service.close()


@pytest.mark.asyncio
async def test_seed_recent_content_propagates_fetch_error(monkeypatch):
    # A fetch failure must propagate so add_source() falls back to background.
    service = SyncService(session=None)
    monkeypatch.setattr(
        service, "_fetch_feed_content", AsyncMock(side_effect=RuntimeError("boom"))
    )
    source = Source(
        id=uuid4(),
        name="Blog",
        url="https://b.ex",
        feed_url="https://b.ex/feed",
        type=SourceType.ARTICLE,
    )
    with pytest.raises(RuntimeError):
        await service.seed_recent_content(source)
    await service.close()
