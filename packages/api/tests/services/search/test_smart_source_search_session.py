"""Session-lifecycle tests for SmartSourceSearchService.

These verify the "release DB session before slow externals" pattern (mirrors
PR #485 on the digest hot path). The injected request-scoped session must be
handed back to the pool BEFORE any LLM/HTTP layer runs, otherwise the pool
saturates under burst load (3× QueuePool TimeoutError on 2026-04-27).
"""

from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import AsyncMock, patch
from uuid import uuid4

import pytest

from app.services.search.smart_source_search import SmartSourceSearchService


class _FakeSession:
    """Minimal AsyncSession stand-in tracking close() vs other ops ordering."""

    def __init__(self) -> None:
        self.events: list[str] = []
        self.closed = False

    async def execute(self, *args, **kwargs):
        self.events.append("execute")

        class _R:
            def fetchone(self_inner):
                return None

            def fetchall(self_inner):
                return []

        return _R()

    async def commit(self) -> None:
        self.events.append("commit")

    async def rollback(self) -> None:
        self.events.append("rollback")

    async def close(self) -> None:
        self.events.append("close")
        self.closed = True


def _make_service(db: _FakeSession, *, on_phase1_done=None) -> SmartSourceSearchService:
    return SmartSourceSearchService(db, on_phase1_done=on_phase1_done)


@pytest.mark.asyncio
async def test_release_session_calls_hook_once():
    db = _FakeSession()
    calls = {"n": 0}

    async def hook() -> None:
        calls["n"] += 1
        await db.close()

    svc = _make_service(db, on_phase1_done=hook)
    await svc._release_session()
    await svc._release_session()  # idempotent
    assert calls["n"] == 1
    assert db.closed is True


@pytest.mark.asyncio
async def test_release_session_no_hook_safe():
    db = _FakeSession()
    svc = _make_service(db, on_phase1_done=None)
    await svc._release_session()  # must not raise
    assert svc._session_released is True


@pytest.mark.asyncio
async def test_search_releases_before_externals():
    """When phase 2 runs, the injected session must already be closed."""
    db = _FakeSession()
    user_id = str(uuid4())

    closed_when_brave_called: list[bool] = []

    async def fake_brave(self, query, user_themes):
        closed_when_brave_called.append(db.closed)
        return []

    async def hook() -> None:
        await db.close()

    svc = _make_service(db, on_phase1_done=hook)

    # Stub all expensive paths so we exercise the orchestrator only.
    with (
        patch.object(
            SmartSourceSearchService,
            "_get_user_themes",
            new=AsyncMock(return_value=[]),
        ),
        patch.object(
            SmartSourceSearchService,
            "_search_catalog",
            new=AsyncMock(return_value=[]),
        ),
        patch.object(
            SmartSourceSearchService,
            "_search_brave",
            new=fake_brave,
        ),
        patch.object(
            SmartSourceSearchService,
            "_search_google_news",
            new=AsyncMock(return_value=[]),
        ),
        patch.object(
            SmartSourceSearchService,
            "_search_mistral",
            new=AsyncMock(return_value=[]),
        ),
        patch(
            "app.services.search.smart_source_search.search_cache_get",
            new=AsyncMock(return_value=None),
        ),
        patch(
            "app.services.search.smart_source_search.search_cache_set",
            new=AsyncMock(return_value=None),
        ),
        patch(
            "app.services.search.smart_source_search._record_search_log",
            new=AsyncMock(return_value=None),
        ),
    ):
        # The brave provider readiness check looks at self.brave.is_ready;
        # swap in a stub that reports ready so the layer runs in expand mode.
        svc.brave = SimpleNamespace(is_ready=True)  # type: ignore[assignment]
        await svc.search(
            "test-query-no-match",
            user_id,
            content_type=None,
            expand=True,  # forces external pipeline
        )

    # Brave was called → assert session was closed by then.
    assert closed_when_brave_called, "brave layer never ran"
    assert all(closed_when_brave_called), (
        "DB session was still open when phase-2 externals started — "
        "release-before-externals contract violated"
    )


@pytest.mark.asyncio
async def test_short_circuit_path_also_releases():
    """Strong-catalog short-circuit must also release before _finalize side-effects."""
    db = _FakeSession()
    user_id = str(uuid4())

    strong_match = {
        "name": "stratechery",
        "url": "https://stratechery.com",
        "feed_url": "https://stratechery.com/feed",
        "type": "article",
        "in_catalog": True,
        "is_curated": True,
        "score": 0.9,
        "source_layer": "catalog",
        "_similarity": 1.0,
    }

    released = {"flag": False}

    async def hook() -> None:
        released["flag"] = True
        await db.close()

    svc = _make_service(db, on_phase1_done=hook)

    with (
        patch.object(
            SmartSourceSearchService,
            "_get_user_themes",
            new=AsyncMock(return_value=[]),
        ),
        patch.object(
            SmartSourceSearchService,
            "_search_catalog",
            new=AsyncMock(return_value=[strong_match]),
        ),
        patch(
            "app.services.search.smart_source_search.search_cache_get",
            new=AsyncMock(return_value=None),
        ),
        patch(
            "app.services.search.smart_source_search.search_cache_set",
            new=AsyncMock(return_value=None),
        ),
        patch(
            "app.services.search.smart_source_search._record_search_log",
            new=AsyncMock(return_value=None),
        ),
    ):
        await svc.search("stratechery", user_id, content_type=None, expand=False)

    assert released["flag"] is True
    assert db.closed is True


@pytest.mark.asyncio
async def test_cache_hit_releases_session():
    db = _FakeSession()
    user_id = str(uuid4())

    released = {"flag": False}

    async def hook() -> None:
        released["flag"] = True
        await db.close()

    svc = _make_service(db, on_phase1_done=hook)

    cached_payload = {
        "query_normalized": "x",
        "results": [],
        "cache_hit": False,
        "layers_called": ["catalog"],
        "latency_ms": 0,
    }

    with (
        patch(
            "app.services.search.smart_source_search.search_cache_get",
            new=AsyncMock(return_value=cached_payload),
        ),
        patch(
            "app.services.search.smart_source_search._record_search_log",
            new=AsyncMock(return_value=None),
        ),
    ):
        out = await svc.search("x", user_id, content_type=None, expand=False)

    assert out["cache_hit"] is True
    assert released["flag"] is True


@pytest.mark.asyncio
async def test_double_close_is_safe():
    db = _FakeSession()

    async def hook() -> None:
        await db.close()
        await db.close()  # idempotent on real AsyncSession too

    svc = _make_service(db, on_phase1_done=hook)
    await svc._release_session()
    assert db.events.count("close") == 2
