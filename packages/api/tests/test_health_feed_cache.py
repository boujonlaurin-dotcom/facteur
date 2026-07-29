"""Tests for /api/health/feed-cache — feed cache observability endpoint.

Mirror of `test_health_pool.py`. Without it, a cache hit emitted no signal
at all: impossible to tell whether an invalidation or TTL change improved
anything. The endpoint must:
- Expose the counters dashboards/QA depend on, including `uptime_seconds`
  (the counters are cumulative — a reader needs a time base for the delta).
- Stay open when `HEALTH_METRICS_TOKEN` is unset (staging).
- 404 without the token when it is set (`size` proxies active users).
"""

import pytest
from httpx import ASGITransport, AsyncClient

from app.config import get_settings
from app.main import app


@pytest.fixture(autouse=True)
def _clear_settings_cache():
    """`get_settings` is `lru_cache`d — without this the first test's env
    leaks into the others."""
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


async def _get(headers: dict[str, str] | None = None):
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        return await ac.get("/api/health/feed-cache", headers=headers or {})


@pytest.mark.asyncio
async def test_feed_cache_endpoint_returns_metrics(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.delenv("HEALTH_METRICS_TOKEN", raising=False)

    resp = await _get()

    assert resp.status_code == 200, f"got {resp.status_code}: {resp.text[:200]}"
    body = resp.json()
    for field in (
        "hits",
        "misses",
        "invalidations",
        "size",
        "hit_rate",
        "ttl_seconds",
        "personalized_ttl_seconds",
        "uptime_seconds",
    ):
        assert field in body, field
    assert body["uptime_seconds"] >= 0


@pytest.mark.asyncio
async def test_feed_cache_endpoint_is_open_without_token_env(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Staging has no `HEALTH_METRICS_TOKEN` — a stray header must not gate it."""
    monkeypatch.delenv("HEALTH_METRICS_TOKEN", raising=False)

    resp = await _get({"X-Health-Token": "whatever"})

    assert resp.status_code == 200


@pytest.mark.asyncio
async def test_feed_cache_endpoint_requires_token_when_configured(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("HEALTH_METRICS_TOKEN", "s3cret")

    assert (await _get()).status_code == 404
    assert (await _get({"X-Health-Token": "wrong"})).status_code == 404
    assert (await _get({"X-Health-Token": "s3cret"})).status_code == 200
