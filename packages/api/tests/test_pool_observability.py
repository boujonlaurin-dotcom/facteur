"""Tests Volet 3 — introspection pool (`read_pool_stats`) + sonde périodique
(`_pool_health_probe`). Observabilité scaling (WP-E).
"""

from unittest.mock import MagicMock, patch

import pytest

from app.observability.pool_stats import read_pool_stats


class _FakePool:
    def __init__(self, size, checked_in, checked_out, overflow):
        self._size = size
        self._ci = checked_in
        self._co = checked_out
        self._ov = overflow

    def size(self):
        return self._size

    def checkedin(self):
        return self._ci

    def checkedout(self):
        return self._co

    def overflow(self):
        return self._ov


class _FakeEngine:
    def __init__(self, pool):
        self.pool = pool


def test_read_pool_stats_saturated():
    """checked_out >= size + overflow ⇒ status saturated, usage_pct 100."""
    stats = read_pool_stats(_FakeEngine(_FakePool(size=10, checked_in=0, checked_out=20, overflow=10)))
    assert stats["status"] == "saturated"
    assert stats["size"] == 10
    assert stats["checked_out"] == 20
    assert stats["usage_pct"] == 100.0


def test_read_pool_stats_ok_with_negative_overflow():
    """QueuePool renvoie un overflow négatif sous capacité ⇒ clamp à 0, ok."""
    stats = read_pool_stats(_FakeEngine(_FakePool(size=10, checked_in=5, checked_out=5, overflow=-5)))
    assert stats["status"] == "ok"
    # usage = 5 / (10 + max(-5, 0)) = 50 %
    assert stats["usage_pct"] == 50.0


def test_read_pool_stats_nullpool_returns_none_fields():
    """NullPool (dev) n'expose pas size()/checkedout() ⇒ champs None, pas de usage_pct."""
    stats = read_pool_stats(_FakeEngine(object()))
    assert stats["status"] == "ok"
    assert stats["size"] is None
    assert stats["checked_out"] is None
    assert "usage_pct" not in stats


@pytest.mark.asyncio
async def test_pool_probe_alerts_above_threshold():
    """usage_pct >= seuil ⇒ warning structlog + capture_message Sentry."""
    from app.workers import scheduler as scheduler_mod

    fake_stats = {"status": "ok", "size": 10, "checked_out": 9, "usage_pct": 90.0}
    fake_sentry = MagicMock()
    with (
        patch("app.observability.pool_stats.read_pool_stats", return_value=fake_stats),
        patch.dict("sys.modules", {"sentry_sdk": fake_sentry}),
        patch.object(scheduler_mod, "settings") as mock_settings,
        patch.object(scheduler_mod, "logger") as mock_logger,
    ):
        mock_settings.pool_alert_threshold_pct = 80
        await scheduler_mod._pool_health_probe()

    assert mock_logger.warning.call_args.args[0] == "db_pool_pressure_high"
    fake_sentry.capture_message.assert_called_once()
    assert fake_sentry.capture_message.call_args.kwargs["level"] == "warning"


@pytest.mark.asyncio
async def test_pool_probe_quiet_below_threshold():
    """usage_pct < seuil ⇒ info db_pool_probe, aucun warning ni Sentry."""
    from app.workers import scheduler as scheduler_mod

    fake_stats = {"status": "ok", "size": 10, "checked_out": 3, "usage_pct": 30.0}
    fake_sentry = MagicMock()
    with (
        patch("app.observability.pool_stats.read_pool_stats", return_value=fake_stats),
        patch.dict("sys.modules", {"sentry_sdk": fake_sentry}),
        patch.object(scheduler_mod, "settings") as mock_settings,
        patch.object(scheduler_mod, "logger") as mock_logger,
    ):
        mock_settings.pool_alert_threshold_pct = 80
        await scheduler_mod._pool_health_probe()

    mock_logger.warning.assert_not_called()
    fake_sentry.capture_message.assert_not_called()
    mock_logger.info.assert_called_once()
    assert mock_logger.info.call_args.args[0] == "db_pool_probe"


@pytest.mark.asyncio
async def test_pool_probe_registered_in_scheduler():
    """Le job doit être dans start_scheduler avec un interval de 5 min."""
    import inspect

    from app.workers import scheduler as scheduler_mod

    src = inspect.getsource(scheduler_mod.start_scheduler)
    assert "_pool_health_probe" in src
    assert 'id="pool_health_probe"' in src
    assert "IntervalTrigger(minutes=5)" in src
