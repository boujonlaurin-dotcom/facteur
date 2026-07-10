"""Tests for FeedPageCache (R5 fix)."""

from __future__ import annotations

import asyncio
from uuid import uuid4

import pytest

from app.services.feed_cache import FeedPageCache


@pytest.fixture
def cache() -> FeedPageCache:
    return FeedPageCache(ttl_seconds=30.0)


def test_get_returns_none_on_miss(cache: FeedPageCache) -> None:
    user = uuid4()
    assert cache.get(user) is None
    assert cache.stats()["misses"] == 1
    assert cache.stats()["hits"] == 0


def test_put_then_get_returns_payload(cache: FeedPageCache) -> None:
    user = uuid4()
    cache.put(user, b'{"items": []}')
    assert cache.get(user) == b'{"items": []}'
    assert cache.stats()["hits"] == 1


def test_invalidate_drops_entry(cache: FeedPageCache) -> None:
    user = uuid4()
    cache.put(user, b"x")
    cache.invalidate(user)
    assert cache.get(user) is None
    assert cache.stats()["invalidations"] == 1


def test_per_user_isolation(cache: FeedPageCache) -> None:
    a, b = uuid4(), uuid4()
    cache.put(a, b"payload-a")
    cache.put(b, b"payload-b")
    assert cache.get(a) == b"payload-a"
    assert cache.get(b) == b"payload-b"
    cache.invalidate(a)
    assert cache.get(a) is None
    assert cache.get(b) == b"payload-b"


def test_ttl_expiry(monkeypatch: pytest.MonkeyPatch) -> None:
    """Entry past its TTL is treated as a miss without being explicitly evicted."""
    cache = FeedPageCache(ttl_seconds=10.0)
    user = uuid4()

    fake_now = [1000.0]

    def fake_monotonic() -> float:
        return fake_now[0]

    monkeypatch.setattr("app.services.feed_cache.time.monotonic", fake_monotonic)

    cache.put(user, b"x")
    assert cache.get(user) == b"x"

    # Advance past TTL
    fake_now[0] += 11.0
    assert cache.get(user) is None


def test_disabled_cache_is_noop() -> None:
    """Both TTLs=0 disables the cache: put/get/invalidate become no-ops."""
    cache = FeedPageCache(ttl_seconds=0.0, personalized_ttl_seconds=0.0)
    assert not cache.enabled
    user = uuid4()
    cache.put(user, b"x")
    assert cache.get(user) is None
    cache.invalidate(user)  # must not raise


def test_invalidate_unknown_user_is_safe(cache: FeedPageCache) -> None:
    cache.invalidate(uuid4())
    assert cache.stats()["invalidations"] == 0


@pytest.mark.asyncio
async def test_single_flight_serializes_concurrent_misses(
    cache: FeedPageCache,
) -> None:
    """The canonical pattern serialises concurrent misses for the same user.

    Simulates 5 concurrent requests for the same user with a 50 ms compute.
    Only the first should observe a miss — the rest pick up the cached
    payload populated under the lock.
    """
    user = uuid4()
    compute_calls = 0

    async def request() -> bytes:
        nonlocal compute_calls
        async with cache.lock(user):
            cached = cache.get(user)
            if cached is not None:
                return cached
            compute_calls += 1
            await asyncio.sleep(0.02)  # simulate DB roundtrip
            payload = f"payload-{compute_calls}".encode()
            cache.put(user, payload)
            return payload

    results = await asyncio.gather(*[request() for _ in range(5)])
    assert compute_calls == 1
    assert all(r == b"payload-1" for r in results)


@pytest.mark.asyncio
async def test_lock_is_per_user(cache: FeedPageCache) -> None:
    """Two different users must NOT serialise on the same lock."""
    a, b = uuid4(), uuid4()
    started_a = asyncio.Event()
    release_a = asyncio.Event()

    async def hold_a() -> None:
        async with cache.lock(a):
            started_a.set()
            await release_a.wait()

    async def quick_b() -> str:
        async with cache.lock(b):
            return "ok"

    task_a = asyncio.create_task(hold_a())
    await started_a.wait()
    # If lock was global, this would block until release_a is set.
    result = await asyncio.wait_for(quick_b(), timeout=0.5)
    release_a.set()
    await task_a
    assert result == "ok"


def test_ttl_from_env_default(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("FEED_CACHE_TTL_SECONDS", raising=False)
    cache = FeedPageCache()
    assert cache.ttl_seconds == 30.0


def test_ttl_from_env_zero_disables(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("FEED_CACHE_TTL_SECONDS", "0")
    cache = FeedPageCache()
    assert not cache.default_enabled


def test_ttl_from_env_invalid_falls_back(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("FEED_CACHE_TTL_SECONDS", "not-a-number")
    cache = FeedPageCache()
    assert cache.ttl_seconds == 30.0


def test_ttl_from_env_negative_clamps_to_zero(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("FEED_CACHE_TTL_SECONDS", "-5")
    cache = FeedPageCache()
    assert cache.ttl_seconds == 0.0
    assert not cache.default_enabled


def test_clear_drops_all(cache: FeedPageCache) -> None:
    a, b = uuid4(), uuid4()
    cache.put(a, b"x")
    cache.put(b, b"y")
    cache.clear()
    assert cache.get(a) is None
    assert cache.get(b) is None


def test_reset_stats(cache: FeedPageCache) -> None:
    user = uuid4()
    cache.put(user, b"x")
    cache.get(user)
    cache.get(uuid4())
    cache.reset_stats()
    s = cache.stats()
    assert s["hits"] == 0
    assert s["misses"] == 0
    assert s["invalidations"] == 0


# --- Personalized variants (app-load slowdown fix) -------------------------


def test_variant_isolated_from_default(cache: FeedPageCache) -> None:
    """A personalized variant and the default view share a user but not a slot."""
    user = uuid4()
    cache.put(user, b"default")
    cache.put(user, b"theme-tech", variant="p|theme=tech")
    assert cache.get(user) == b"default"
    assert cache.get(user, variant="p|theme=tech") == b"theme-tech"


def test_variants_isolated_from_each_other(cache: FeedPageCache) -> None:
    user = uuid4()
    cache.put(user, b"tech", variant="p|theme=tech")
    cache.put(user, b"science", variant="p|theme=science")
    assert cache.get(user, variant="p|theme=tech") == b"tech"
    assert cache.get(user, variant="p|theme=science") == b"science"


def test_invalidate_purges_all_variants(cache: FeedPageCache) -> None:
    """A write invalidation drops the default view AND every personalized
    section for that user, but leaves other users untouched."""
    a, b = uuid4(), uuid4()
    cache.put(a, b"default-a")
    cache.put(a, b"tech-a", variant="p|theme=tech")
    cache.put(a, b"science-a", variant="p|theme=science")
    cache.put(b, b"tech-b", variant="p|theme=tech")

    cache.invalidate(a)

    assert cache.get(a) is None
    assert cache.get(a, variant="p|theme=tech") is None
    assert cache.get(a, variant="p|theme=science") is None
    # One invalidate call == one counted invalidation, regardless of variant count.
    assert cache.stats()["invalidations"] == 1
    # Other users are not collateral.
    assert cache.get(b, variant="p|theme=tech") == b"tech-b"


def test_variant_lock_is_per_variant(cache: FeedPageCache) -> None:
    """Locks are keyed by (user, variant): different variants get distinct locks."""
    user = uuid4()
    lock_default = cache.lock(user)
    lock_tech = cache.lock(user, variant="p|theme=tech")
    lock_tech_again = cache.lock(user, variant="p|theme=tech")
    assert lock_default is not lock_tech
    assert lock_tech is lock_tech_again


def test_personalized_ttl_independent_kill_switch(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Default TTL=0 + personalized TTL>0: default puts are no-ops, personalized
    puts are cached (and vice-versa)."""
    cache = FeedPageCache(ttl_seconds=0.0, personalized_ttl_seconds=60.0)
    assert cache.enabled
    assert not cache.default_enabled
    assert cache.personalized_enabled
    user = uuid4()
    cache.put(user, b"default")  # no-op (default disabled)
    cache.put(user, b"tech", variant="p|theme=tech")
    assert cache.get(user) is None
    assert cache.get(user, variant="p|theme=tech") == b"tech"


def test_personalized_ttl_from_env_default(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("FEED_CACHE_PERSONALIZED_TTL_SECONDS", raising=False)
    cache = FeedPageCache()
    assert cache.personalized_ttl_seconds == 60.0


def test_personalized_ttl_from_env_zero_disables(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("FEED_CACHE_PERSONALIZED_TTL_SECONDS", "0")
    cache = FeedPageCache()
    assert not cache.personalized_enabled


def test_personalized_variant_uses_personalized_ttl(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A personalized entry expires on the personalized TTL, not the default."""
    cache = FeedPageCache(ttl_seconds=30.0, personalized_ttl_seconds=60.0)
    user = uuid4()

    fake_now = [1000.0]
    monkeypatch.setattr("app.services.feed_cache.time.monotonic", lambda: fake_now[0])

    cache.put(user, b"tech", variant="p|theme=tech")
    # Past the default TTL (30s) but within the personalized TTL (60s).
    fake_now[0] += 45.0
    assert cache.get(user, variant="p|theme=tech") == b"tech"
    # Past the personalized TTL.
    fake_now[0] += 20.0
    assert cache.get(user, variant="p|theme=tech") is None
