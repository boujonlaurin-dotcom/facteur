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
async def test_pasted_url_with_feed_short_circuits_direct():
    """A pasted URL that resolves to a feed returns via the `direct` layer,
    skipping catalog and every external provider."""
    db = _FakeSession()
    user_id = str(uuid4())

    catalog_calls = {"n": 0}
    brave_calls = {"n": 0}

    async def spy_catalog(self, *a, **k):
        catalog_calls["n"] += 1
        return []

    async def spy_brave(self, *a, **k):
        brave_calls["n"] += 1
        return []

    async def fake_detect(self, url):
        return (
            "https://www.usine-digitale.fr",
            {
                "feed_url": "https://www.usine-digitale.fr/rss",
                "name": "L'Usine Digitale",
                "type": "article",
            },
        )

    async def hook() -> None:
        await db.close()

    svc = _make_service(db, on_phase1_done=hook)

    with (
        patch.object(
            SmartSourceSearchService,
            "_get_user_themes",
            new=AsyncMock(return_value=[]),
        ),
        patch.object(SmartSourceSearchService, "_search_catalog", new=spy_catalog),
        patch.object(
            SmartSourceSearchService,
            "_detect_with_root_fallback",
            new=fake_detect,
        ),
        patch.object(SmartSourceSearchService, "_search_brave", new=spy_brave),
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
        svc.brave = SimpleNamespace(is_ready=True)  # type: ignore[assignment]
        out = await svc.search(
            "https://www.usine-digitale.fr/", user_id, content_type=None, expand=False
        )

    assert out["layers_called"] == ["direct"]
    assert catalog_calls["n"] == 0
    assert brave_calls["n"] == 0
    assert len(out["results"]) == 1
    assert out["results"][0]["source_layer"] == "direct"


@pytest.mark.asyncio
async def test_pasted_url_without_feed_falls_through_to_catalog():
    """A URL with no discoverable feed must NOT return empty — it falls
    through to the normal pipeline (catalog first)."""
    db = _FakeSession()
    user_id = str(uuid4())

    catalog_calls = {"n": 0}

    async def spy_catalog(self, *a, **k):
        catalog_calls["n"] += 1
        return []

    async def fake_detect_none(self, url):
        return None

    async def hook() -> None:
        await db.close()

    svc = _make_service(db, on_phase1_done=hook)

    with (
        patch.object(
            SmartSourceSearchService,
            "_get_user_themes",
            new=AsyncMock(return_value=[]),
        ),
        patch.object(SmartSourceSearchService, "_search_catalog", new=spy_catalog),
        patch.object(
            SmartSourceSearchService,
            "_detect_with_root_fallback",
            new=fake_detect_none,
        ),
        patch.object(
            SmartSourceSearchService,
            "_search_brave",
            new=AsyncMock(return_value=[]),
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
        svc.brave = SimpleNamespace(is_ready=True)  # type: ignore[assignment]
        out = await svc.search(
            "https://no-feed-host.example.com/",
            user_id,
            content_type=None,
            expand=False,
        )

    assert "direct" not in out["layers_called"]
    assert "catalog" in out["layers_called"]
    assert catalog_calls["n"] == 1


@pytest.mark.asyncio
async def test_youtube_filter_always_fires_layer():
    """content_type='youtube' fires the YouTube layer even without a text
    heuristic hit, and skips the external providers."""
    db = _FakeSession()
    user_id = str(uuid4())

    yt_calls = {"n": 0}
    brave_calls = {"n": 0}

    async def spy_youtube(self, query, user_themes):
        yt_calls["n"] += 1
        return [
            {
                "name": "Micode",
                "type": "youtube",
                "url": "https://www.youtube.com/@micode",
                "feed_url": "https://www.youtube.com/feeds/videos.xml?channel_id=X",
                "in_catalog": False,
                "score": 0.9,
                "source_layer": "youtube",
            }
        ]

    async def spy_brave(self, *a, **k):
        brave_calls["n"] += 1
        return []

    async def hook() -> None:
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
            new=AsyncMock(return_value=[]),
        ),
        patch.object(SmartSourceSearchService, "_search_youtube", new=spy_youtube),
        patch.object(SmartSourceSearchService, "_search_brave", new=spy_brave),
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
        svc.brave = SimpleNamespace(is_ready=True)  # type: ignore[assignment]
        out = await svc.search(
            "micode", user_id, content_type="youtube", expand=False
        )

    assert "youtube" in out["layers_called"]
    assert yt_calls["n"] == 1
    assert brave_calls["n"] == 0  # content_type filter → externals skipped


@pytest.mark.asyncio
async def test_youtube_layer_not_fired_without_filter_or_heuristic():
    """Regression: content_type=None + a plain word must NOT fire YouTube."""
    db = _FakeSession()
    user_id = str(uuid4())

    yt_calls = {"n": 0}

    async def spy_youtube(self, query, user_themes):
        yt_calls["n"] += 1
        return []

    async def hook() -> None:
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
            new=AsyncMock(return_value=[]),
        ),
        patch.object(SmartSourceSearchService, "_search_youtube", new=spy_youtube),
        patch.object(
            SmartSourceSearchService,
            "_search_brave",
            new=AsyncMock(return_value=[]),
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
        svc.brave = SimpleNamespace(is_ready=True)  # type: ignore[assignment]
        out = await svc.search("micode", user_id, content_type=None, expand=False)

    assert "youtube" not in out["layers_called"]
    assert yt_calls["n"] == 0


@pytest.mark.asyncio
async def test_double_close_is_safe():
    db = _FakeSession()

    async def hook() -> None:
        await db.close()
        await db.close()  # idempotent on real AsyncSession too

    svc = _make_service(db, on_phase1_done=hook)
    await svc._release_session()
    assert db.events.count("close") == 2
