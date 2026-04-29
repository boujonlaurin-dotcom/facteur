"""Tests pour le zombie_session_sweeper (Layer C du hot fix 2026-04-28).

Le sweeper est exécuté toutes les 5 min par APScheduler. Il sert de
filet de sécurité par-dessus :
- Layer A (rollback() en finally dans `safe_async_session`)
- Layer B (`idle_in_transaction_session_timeout=60000` côté Postgres)

Si jamais une couche est contournée (config drift Supavisor, code
externe, etc.), le sweeper rattrape la fuite avant que les zombies ne
saturent les 60 slots du pooler.
"""

from contextlib import asynccontextmanager
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.workers.scheduler import _zombie_session_sweeper


def _make_session_maker(execute_result=None, execute_side_effect=None):
    mock_session = AsyncMock()
    if execute_side_effect is not None:
        mock_session.execute = AsyncMock(side_effect=execute_side_effect)
    else:
        mock_session.execute = AsyncMock(return_value=execute_result)

    @asynccontextmanager
    async def fake_sm():
        yield mock_session

    return fake_sm, mock_session


@pytest.mark.asyncio
async def test_sweeper_kills_zombies_and_logs_warning():
    """Si pg_stat_activity remonte des zombies, log warning + count."""
    fake_rows = [
        (True, 12345, 360),
        (True, 12346, 420),
    ]
    fake_result = MagicMock()
    fake_result.fetchall = MagicMock(return_value=fake_rows)
    fake_sm, mock_session = _make_session_maker(execute_result=fake_result)

    with (
        patch("app.database.safe_async_session", side_effect=lambda: fake_sm()),
        patch("app.workers.scheduler.logger") as mock_logger,
    ):
        await _zombie_session_sweeper()

    # SQL bien envoyé
    assert mock_session.execute.await_count == 1
    sql = str(mock_session.execute.await_args.args[0])
    assert "pg_terminate_backend" in sql
    assert "idle in transaction" in sql
    assert "Supavisor" in sql

    # Logged warning avec les bons pids
    mock_logger.warning.assert_called_once()
    name, kwargs = mock_logger.warning.call_args[0][0], mock_logger.warning.call_args[1]
    assert name == "zombie_session_sweeper_killed"
    assert kwargs["count"] == 2
    assert kwargs["pids"] == [12345, 12346]
    assert kwargs["max_idle_s"] == 420


@pytest.mark.asyncio
async def test_sweeper_logs_clean_when_no_zombies():
    """Aucun zombie détecté = log debug, pas de warning."""
    fake_result = MagicMock()
    fake_result.fetchall = MagicMock(return_value=[])
    fake_sm, _ = _make_session_maker(execute_result=fake_result)

    with (
        patch("app.database.safe_async_session", side_effect=lambda: fake_sm()),
        patch("app.workers.scheduler.logger") as mock_logger,
    ):
        await _zombie_session_sweeper()

    mock_logger.warning.assert_not_called()
    mock_logger.debug.assert_called_once_with("zombie_session_sweeper_clean")


@pytest.mark.asyncio
async def test_sweeper_swallows_exceptions():
    """Une erreur DB ne doit jamais crasher le scheduler — sinon le
    sweeper s'arrête et c'est précisément lui qui devrait sauver l'app.
    """
    fake_sm, _ = _make_session_maker(execute_side_effect=RuntimeError("db down"))

    with (
        patch("app.database.safe_async_session", side_effect=lambda: fake_sm()),
        patch("app.workers.scheduler.logger") as mock_logger,
    ):
        await _zombie_session_sweeper()  # MUST NOT raise

    mock_logger.exception.assert_called_once_with("zombie_session_sweeper_failed")


@pytest.mark.asyncio
async def test_sweeper_registered_in_scheduler():
    """Le job doit être dans la définition de start_scheduler avec
    un interval de 5 min.
    """
    import inspect

    from app.workers import scheduler as scheduler_mod

    src = inspect.getsource(scheduler_mod.start_scheduler)
    assert "_zombie_session_sweeper" in src
    assert 'id="zombie_session_sweeper"' in src
    assert "IntervalTrigger(minutes=5)" in src
