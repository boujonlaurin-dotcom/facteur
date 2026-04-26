"""Resilience tests for ``GET /sources``.

Covers the three layers introduced to absorb the recurring DB-pool issues
visible in Sentry (PYTHON-4, PYTHON-14, PYTHON-26, PYTHON-27/1Q) :

1. ``app.utils.db_retry.retry_db_op`` — transient error retries.
2. ``app.services.sources_cache.SOURCES_CACHE`` — TTL cache.
3. ``app.routers.sources.get_sources`` — wires both together and returns
   503 ``sources_unavailable`` when the DB stays down.
"""

from __future__ import annotations

import asyncio
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4

import pytest
from fastapi import HTTPException
from sqlalchemy.exc import OperationalError

from app.schemas.source import SourceCatalogResponse
from app.services.sources_cache import SOURCES_CACHE, SourcesCache
from app.utils.db_retry import retry_db_op


def _op_error(msg: str = "boom") -> OperationalError:
    return OperationalError("SELECT 1", {}, Exception(msg))


@pytest.fixture(autouse=True)
def _reset_sources_cache():
    SOURCES_CACHE.clear()
    yield
    SOURCES_CACHE.clear()


# ─── retry_db_op ────────────────────────────────────────────────────────


class TestRetryDbOp:
    @pytest.mark.asyncio
    async def test_succeeds_on_first_try(self):
        session = MagicMock()
        session.rollback = AsyncMock()
        op = AsyncMock(return_value="ok")

        result = await retry_db_op(op, session=session, op_name="test")

        assert result == "ok"
        op.assert_awaited_once()
        session.rollback.assert_not_called()

    @pytest.mark.asyncio
    async def test_succeeds_after_two_transient_errors(self):
        session = MagicMock()
        session.rollback = AsyncMock()
        op = AsyncMock(side_effect=[_op_error(), _op_error(), "ok"])

        result = await retry_db_op(
            op, session=session, op_name="test", base_delay=0.0, max_delay=0.0
        )

        assert result == "ok"
        assert op.await_count == 3
        assert session.rollback.await_count == 2

    @pytest.mark.asyncio
    async def test_exhausts_after_max_attempts(self):
        session = MagicMock()
        session.rollback = AsyncMock()
        op = AsyncMock(side_effect=_op_error("final"))

        with pytest.raises(OperationalError):
            await retry_db_op(
                op,
                session=session,
                op_name="test",
                max_attempts=3,
                base_delay=0.0,
                max_delay=0.0,
            )

        assert op.await_count == 3
        assert session.rollback.await_count == 3

    @pytest.mark.asyncio
    async def test_swallows_rollback_failure(self):
        """A failing rollback (already-dead connection) must not mask the
        original transient error."""
        session = MagicMock()
        session.rollback = AsyncMock(side_effect=RuntimeError("conn dead"))
        op = AsyncMock(side_effect=[_op_error(), "ok"])

        result = await retry_db_op(
            op, session=session, op_name="test", base_delay=0.0, max_delay=0.0
        )

        assert result == "ok"
        assert op.await_count == 2

    @pytest.mark.asyncio
    async def test_does_not_retry_on_non_transient_error(self):
        session = MagicMock()
        session.rollback = AsyncMock()
        op = AsyncMock(side_effect=ValueError("not a DB error"))

        with pytest.raises(ValueError):
            await retry_db_op(
                op, session=session, op_name="test", base_delay=0.0, max_delay=0.0
            )

        op.assert_awaited_once()
        session.rollback.assert_not_called()


# ─── SourcesCache ──────────────────────────────────────────────────────


class TestSourcesCache:
    def test_miss_then_hit(self):
        cache = SourcesCache(ttl_seconds=30.0)
        uid = uuid4()
        payload = SourceCatalogResponse(curated=[], custom=[])

        assert cache.get(uid) is None
        cache.put(uid, payload)
        assert cache.get(uid) is payload

    def test_invalidate(self):
        cache = SourcesCache(ttl_seconds=30.0)
        uid = uuid4()
        cache.put(uid, SourceCatalogResponse(curated=[], custom=[]))

        cache.invalidate(uid)

        assert cache.get(uid) is None

    @pytest.mark.asyncio
    async def test_expires(self):
        cache = SourcesCache(ttl_seconds=0.05)
        uid = uuid4()
        cache.put(uid, SourceCatalogResponse(curated=[], custom=[]))

        assert cache.get(uid) is not None
        await asyncio.sleep(0.1)
        assert cache.get(uid) is None

    def test_disabled_when_ttl_zero(self):
        cache = SourcesCache(ttl_seconds=0.0)
        uid = uuid4()

        cache.put(uid, SourceCatalogResponse(curated=[], custom=[]))

        assert cache.get(uid) is None
        assert not cache.enabled

    def test_stats_track_hit_rate(self):
        cache = SourcesCache(ttl_seconds=30.0)
        uid = uuid4()
        cache.put(uid, SourceCatalogResponse(curated=[], custom=[]))

        cache.get(uid)  # hit
        cache.get(uuid4())  # miss
        cache.get(uid)  # hit

        stats = cache.stats()
        assert stats["hits"] == 2
        assert stats["misses"] == 1
        assert stats["hit_rate"] == pytest.approx(2 / 3)


# ─── get_sources router ────────────────────────────────────────────────


class TestGetSourcesEndpoint:
    @pytest.mark.asyncio
    async def test_returns_503_when_db_keeps_failing(self):
        from app.routers import sources as sources_mod

        user_id = str(uuid4())
        db = MagicMock()
        db.rollback = AsyncMock()

        failing_service = MagicMock()
        failing_service.get_all_sources = AsyncMock(side_effect=_op_error("pool gone"))

        with patch.object(
            sources_mod, "SourceService", MagicMock(return_value=failing_service)
        ), pytest.raises(HTTPException) as exc_info:
            await sources_mod.get_sources(user_id=user_id, db=db)

        assert exc_info.value.status_code == 503
        assert exc_info.value.detail == "sources_unavailable"
        # 3 attempts inside retry_db_op
        assert failing_service.get_all_sources.await_count == 3

    @pytest.mark.asyncio
    async def test_returns_200_when_retry_recovers(self):
        from app.routers import sources as sources_mod

        user_id = str(uuid4())
        db = MagicMock()
        db.rollback = AsyncMock()

        payload = SourceCatalogResponse(curated=[], custom=[])
        recovering_service = MagicMock()
        recovering_service.get_all_sources = AsyncMock(
            side_effect=[_op_error(), payload]
        )

        with patch.object(
            sources_mod, "SourceService", MagicMock(return_value=recovering_service)
        ):
            result = await sources_mod.get_sources(user_id=user_id, db=db)

        assert result is payload
        assert recovering_service.get_all_sources.await_count == 2
        # Cache populated on success
        assert SOURCES_CACHE.get(__import__("uuid").UUID(user_id)) is payload

    @pytest.mark.asyncio
    async def test_cache_hit_skips_db(self):
        from uuid import UUID

        from app.routers import sources as sources_mod

        user_id = str(uuid4())
        db = MagicMock()
        payload = SourceCatalogResponse(curated=[], custom=[])
        SOURCES_CACHE.put(UUID(user_id), payload)

        service_factory = MagicMock()

        with patch.object(sources_mod, "SourceService", service_factory):
            result = await sources_mod.get_sources(user_id=user_id, db=db)

        assert result is payload
        # Service must not even be instantiated
        service_factory.assert_not_called()
