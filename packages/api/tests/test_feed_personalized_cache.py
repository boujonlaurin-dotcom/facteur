"""Unit tests for the personalized-section cache eligibility + variant key
(app-load slowdown fix), plus the per-request `feed_request` log."""

from __future__ import annotations

import asyncio
from uuid import uuid4

import pytest
import pytest_asyncio
import structlog
from httpx import ASGITransport, AsyncClient

from app.models.enums import ContentType, FeedFilterMode
from app.routers.feed import (
    _is_default_view,
    _is_personalized_section_view,
    _personalized_variant,
)


def _section_kwargs(**overrides):
    """A baseline personalized theme-section call (the cold-open shape)."""
    base = {
        "offset": 0,
        "content_type": None,
        "mode": None,
        "theme": "tech",
        "topic": None,
        "saved_only": False,
        "has_note": False,
        "source_id": None,
        "entity": None,
        "keyword": None,
        "include_unfollowed": False,
        "followed_only": False,
        "personalized": True,
    }
    base.update(overrides)
    return base


def test_theme_section_is_eligible() -> None:
    assert _is_personalized_section_view(**_section_kwargs())


def test_topic_section_is_eligible() -> None:
    assert _is_personalized_section_view(
        **_section_kwargs(theme=None, topic="123e4567-e89b-12d3-a456-426614174000")
    )


def test_source_section_is_eligible() -> None:
    assert _is_personalized_section_view(
        **_section_kwargs(theme=None, source_id="src-uuid")
    )


def test_not_eligible_without_personalized() -> None:
    assert not _is_personalized_section_view(**_section_kwargs(personalized=False))


def test_not_eligible_with_offset() -> None:
    """Pagination (loadMoreTheme) must bypass the cache."""
    assert not _is_personalized_section_view(**_section_kwargs(offset=20))


def test_not_eligible_with_two_selectors() -> None:
    """Ambiguous selector (theme + source) is not cached."""
    assert not _is_personalized_section_view(
        **_section_kwargs(theme="tech", source_id="src-uuid")
    )


def test_not_eligible_with_no_selector() -> None:
    assert not _is_personalized_section_view(**_section_kwargs(theme=None))


def test_not_eligible_with_extra_filters() -> None:
    for override in (
        {"saved_only": True},
        {"has_note": True},
        {"entity": "Macron"},
        {"keyword": "ia"},
        {"include_unfollowed": True},
        {"followed_only": True},
        {"mode": FeedFilterMode.INSPIRATION},
        {"content_type": ContentType.ARTICLE},
    ):
        assert not _is_personalized_section_view(**_section_kwargs(**override)), (
            override
        )


def test_personalized_view_is_not_default_view() -> None:
    """A personalized section must never match the default-view predicate
    (else it would collide on the variant=None key)."""
    assert not _is_default_view(
        limit=12,
        offset=0,
        content_type=None,
        mode=None,
        serein=False,
        theme="tech",
        topic=None,
        saved_only=False,
        has_note=False,
        source_id=None,
        entity=None,
        keyword=None,
        personalized=True,
    )


def test_variant_is_stable_and_distinct() -> None:
    base = {
        "theme": "tech",
        "topic": None,
        "source_id": None,
        "serein": False,
        "limit": 12,
    }
    v1 = _personalized_variant(**base)
    v2 = _personalized_variant(**base)
    assert v1 == v2  # deterministic
    # Each axis changes the key.
    assert v1 != _personalized_variant(**{**base, "theme": "science"})
    assert v1 != _personalized_variant(**{**base, "serein": True})
    assert v1 != _personalized_variant(**{**base, "limit": 20})
    assert v1 != _personalized_variant(
        **{**base, "theme": None, "source_id": "src-uuid"}
    )


def test_variant_is_never_none() -> None:
    """Always non-None so it never collides with the default-view key."""
    v = _personalized_variant(
        theme=None, topic=None, source_id="src", serein=True, limit=12
    )
    assert isinstance(v, str) and v


# --- `feed_request` log ----------------------------------------------------
#
# `feed_total` is emitted by `_compute_feed`, so a cache hit used to produce
# no log line at all — the hit rate was invisible and no decision on TTL or
# invalidation scope could be grounded. These tests pin the one line every
# request now emits.


@pytest_asyncio.fixture
async def feed_client(monkeypatch, feed_response_factory):
    """Client hitting `/api/feed/` with the recommendation pipeline stubbed.

    The log is what's under test, not the pipeline — stubbing `_compute_feed`
    keeps these tests DB-free and fast.
    """
    from app.database import get_feed_db
    from app.dependencies import get_current_user_id
    from app.main import app

    async def _fake_compute(**_kwargs):
        return feed_response_factory(items=3)

    monkeypatch.setattr("app.routers.feed._compute_feed", _fake_compute)

    user_id = uuid4()

    async def _fake_user():
        return str(user_id)

    async def _fake_db():
        yield None

    app.dependency_overrides[get_current_user_id] = _fake_user
    app.dependency_overrides[get_feed_db] = _fake_db
    try:
        async with AsyncClient(
            transport=ASGITransport(app=app), base_url="http://test"
        ) as ac:
            yield ac
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)
        app.dependency_overrides.pop(get_feed_db, None)


def _feed_requests(logs: list[dict]) -> list[dict]:
    return [entry for entry in logs if entry.get("event") == "feed_request"]


@pytest.mark.asyncio
async def test_logs_miss_then_hit_on_personalized_section(feed_client) -> None:
    url = "/api/feed/?personalized=true&theme=tech&limit=12"

    with structlog.testing.capture_logs() as logs:
        assert (await feed_client.get(url)).status_code == 200
        assert (await feed_client.get(url)).status_code == 200

    miss, hit = _feed_requests(logs)
    assert miss["cache"] == "miss"
    assert miss["variant_class"] == "personalized"
    assert miss["items"] == 3
    assert miss["duration_ms"] >= 0
    assert hit["cache"] == "hit"
    assert hit["variant_class"] == "personalized"


@pytest.mark.asyncio
async def test_logs_default_view_class(feed_client) -> None:
    with structlog.testing.capture_logs() as logs:
        assert (await feed_client.get("/api/feed/?limit=20")).status_code == 200

    (entry,) = _feed_requests(logs)
    assert entry["cache"] == "miss"
    assert entry["variant_class"] == "default"


@pytest.mark.asyncio
async def test_logs_bypass_for_non_cacheable_view(feed_client) -> None:
    """Paginated fetches skip the cache entirely — they must still be counted,
    else the hit rate reads as better than it is."""
    with structlog.testing.capture_logs() as logs:
        resp = await feed_client.get("/api/feed/?offset=20&limit=20")
        assert resp.status_code == 200

    (entry,) = _feed_requests(logs)
    assert entry["cache"] == "bypass"
    assert entry["variant_class"] == "none"
    assert entry["items"] == 3


@pytest.mark.asyncio
async def test_concurrent_misses_compute_once_and_touch_db_after_lock(
    feed_client, monkeypatch, feed_response_factory
) -> None:
    """Same-key misses wait without DB work, then consume the first result."""
    from app.database import get_feed_db
    from app.dependencies import get_current_user_id
    from app.main import app
    from app.services.feed_cache import FEED_CACHE

    user_id = uuid4()
    variant = _personalized_variant(
        theme="tech", topic=None, source_id=None, serein=False, limit=12
    )
    single_flight_lock = FEED_CACHE.lock(user_id, variant)
    compute_started = asyncio.Event()
    release_compute = asyncio.Event()
    compute_calls = 0
    db_access_while_locked: list[bool] = []

    class TrackingSession:
        async def execute(self, *_args, **_kwargs):
            db_access_while_locked.append(single_flight_lock.locked())

    session = TrackingSession()

    async def _fake_user():
        return str(user_id)

    async def _fake_db():
        yield session

    async def _fake_compute(*, db, **_kwargs):
        nonlocal compute_calls
        compute_calls += 1
        # Represents `_resolve_topic_param` / the first service SELECT.
        await db.execute("first-business-read")
        compute_started.set()
        await release_compute.wait()
        return feed_response_factory(items=3)

    app.dependency_overrides[get_current_user_id] = _fake_user
    app.dependency_overrides[get_feed_db] = _fake_db
    monkeypatch.setattr("app.routers.feed._compute_feed", _fake_compute)

    url = "/api/feed/?personalized=true&theme=tech&limit=12"
    tasks = [asyncio.create_task(feed_client.get(url)) for _ in range(5)]
    await asyncio.wait_for(compute_started.wait(), timeout=1)
    # Give the other requests a scheduling turn to reach the held lock.
    await asyncio.sleep(0)
    release_compute.set()
    responses = await asyncio.gather(*tasks)

    assert [response.status_code for response in responses] == [200] * 5
    assert all(response.json() == responses[0].json() for response in responses)
    assert compute_calls == 1
    assert db_access_while_locked == [True]
