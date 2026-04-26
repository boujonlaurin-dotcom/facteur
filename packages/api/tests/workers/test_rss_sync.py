"""Tests pour app.workers.rss_sync — focus : libération de la session outer."""

from unittest.mock import AsyncMock, MagicMock, patch

import pytest


def _make_session_cm():
    """Build a mock async_session_maker() that tracks rollback/commit on the
    session yielded to the worker.
    """
    session = AsyncMock()
    session.rollback = AsyncMock()
    session.commit = AsyncMock()
    session.close = AsyncMock()

    cm = MagicMock()
    cm.__aenter__ = AsyncMock(return_value=session)
    cm.__aexit__ = AsyncMock(return_value=None)

    maker = MagicMock(return_value=cm)
    return maker, session


@pytest.mark.asyncio
async def test_sync_all_sources_releases_outer_session():
    """sync_all_sources doit rollback la session outer pour libérer Supavisor.

    Régression : sans rollback explicite, la connexion reste 'idle in
    transaction' jusqu'au pool_recycle (cf. perf-watch 2026-04-26).
    """
    maker, session = _make_session_cm()

    with patch(
        "app.workers.rss_sync.async_session_maker", maker
    ), patch("app.workers.rss_sync.SyncService") as MockService:
        instance = MockService.return_value
        instance.sync_all_sources = AsyncMock(
            return_value={"success": 0, "failed": 0, "total_new": 0}
        )
        instance.close = AsyncMock()

        from app.workers.rss_sync import sync_all_sources

        await sync_all_sources()

    assert (
        session.rollback.await_count + session.commit.await_count >= 1
    ), "outer session was never released (rollback/commit missing) — Supavisor leak"


@pytest.mark.asyncio
async def test_sync_source_releases_outer_session_on_not_found():
    """sync_source doit rollback la session outer même quand la source n'existe pas."""
    maker, session = _make_session_cm()

    exec_result = MagicMock()
    exec_result.scalar_one_or_none = MagicMock(return_value=None)
    session.execute = AsyncMock(return_value=exec_result)

    with patch(
        "app.workers.rss_sync.async_session_maker", maker
    ), patch("app.workers.rss_sync.SyncService") as MockService:
        instance = MockService.return_value
        instance.process_source = AsyncMock()
        instance.close = AsyncMock()

        from app.workers.rss_sync import sync_source

        ok = await sync_source("00000000-0000-0000-0000-000000000000")

    assert ok is False
    assert session.rollback.await_count + session.commit.await_count >= 1
