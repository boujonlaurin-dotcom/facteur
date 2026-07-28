"""Tests Volet 3 — introspection pool (`read_pool_stats`) + sonde périodique
(`_pool_health_probe`). Observabilité scaling (WP-E).
"""

from unittest.mock import MagicMock, patch

import pytest

from app.observability.pool_stats import read_pool_stats


class _FakePool:
    def __init__(self, size, checked_in, checked_out, overflow, max_overflow=10):
        self._size = size
        self._ci = checked_in
        self._co = checked_out
        self._ov = overflow
        # Nom calqué sur SQLAlchemy : `read_pool_stats` lit `_max_overflow`.
        self._max_overflow = max_overflow

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
    """checked_out >= pool_size + max_overflow ⇒ status saturated, usage 100 %."""
    stats = read_pool_stats(
        _FakeEngine(_FakePool(size=10, checked_in=0, checked_out=20, overflow=10))
    )
    assert stats["status"] == "saturated"
    assert stats["size"] == 10
    assert stats["capacity"] == 20
    assert stats["checked_out"] == 20
    assert stats["usage_pct"] == 100.0


def test_read_pool_stats_ok_with_negative_overflow():
    """QueuePool renvoie un overflow négatif sous capacité ⇒ sans effet.

    `overflow()` ne doit jamais entrer dans le calcul : seule la capacité
    (`pool_size + max_overflow` = 20) compte.
    """
    stats = read_pool_stats(
        _FakeEngine(_FakePool(size=10, checked_in=5, checked_out=5, overflow=-5))
    )
    assert stats["status"] == "ok"
    # usage = 5 / 20 = 25 % (et non 5 / (10 + max(-5, 0)) = 50 %)
    assert stats["usage_pct"] == 25.0


def test_read_pool_stats_does_not_page_on_engaged_overflow():
    """Régression PYTHON-63 — l'overflow engagé ne doit pas simuler la saturation.

    Événement réel du 2026-07-25 : `size=10, overflow=2, checked_out=11`, soit
    11 connexions sur une capacité de 20 (55 %). L'ancienne formule divisait par
    `size + overflow()` = 12 et rapportait 91,7 %, déclenchant une alerte Sentry
    `fatal` (seuil page 90 %) alors qu'il restait 9 connexions libres.
    """
    stats = read_pool_stats(
        _FakeEngine(_FakePool(size=10, checked_in=1, checked_out=11, overflow=2))
    )
    assert stats["usage_pct"] == 55.0
    assert stats["status"] == "ok"
    assert stats["capacity"] == 20
    # `overflow` reste exposé pour le diagnostic, mais hors du dénominateur.
    assert stats["overflow"] == 2


def test_read_pool_stats_unbounded_overflow_has_no_usage_pct():
    """max_overflow < 0 (illimité) ⇒ pas de capacité bornée, donc pas de ratio."""
    stats = read_pool_stats(
        _FakeEngine(
            _FakePool(
                size=10, checked_in=0, checked_out=30, overflow=20, max_overflow=-1
            )
        )
    )
    assert stats["capacity"] is None
    assert stats["status"] == "ok"
    assert "usage_pct" not in stats


def test_read_pool_stats_logs_when_sized_pool_has_unreadable_capacity():
    """Un pool dimensionné dont la capacité est illisible doit être BRUYANT.

    `read_pool_stats` lit `max_overflow` sur l'attribut privé `_max_overflow`.
    Si une version de SQLAlchemy le renomme, `usage_pct` disparaît — et la sonde
    de `scheduler.py` prend alors la branche « NullPool » et cesse d'alerter,
    silencieusement. C'est le pire mode de défaillance possible pour une
    métrique d'alerte, donc il doit laisser une trace `error`.
    """
    pool = _FakePool(size=10, checked_in=0, checked_out=8, overflow=0)
    del pool._max_overflow  # simule le renommage de l'attribut privé

    with patch("app.observability.pool_stats.logger") as mock_logger:
        stats = read_pool_stats(_FakeEngine(pool))

    assert stats["capacity"] is None
    assert "usage_pct" not in stats
    assert mock_logger.error.call_args.args[0] == "pool_capacity_unreadable"


def test_read_pool_stats_nullpool_stays_quiet():
    """NullPool n'est pas une anomalie : pas de capacité, mais pas d'erreur."""
    with patch("app.observability.pool_stats.logger") as mock_logger:
        read_pool_stats(_FakeEngine(object()))

    mock_logger.error.assert_not_called()


def test_read_pool_stats_capacity_matches_real_queuepool():
    """Garde-fou sémantique : la capacité est lue sur un VRAI pool SQLAlchemy.

    Les fakes ci-dessus ne protègent pas contre une mécompréhension de l'API
    SQLAlchemy — c'est précisément ce qui a produit PYTHON-63. Ici on construit
    un pool réel avec les kwargs de prod et on vérifie que `read_pool_stats`
    voit bien 20 connexions de capacité, y compris en cours de montée en charge
    (là où `overflow()` est négatif puis positif).
    """
    from sqlalchemy.pool import QueuePool

    from app.database import PROD_POOL_KWARGS

    class _StubDBAPIConnection:
        def rollback(self): ...

        def close(self): ...

    pool = QueuePool(
        lambda: _StubDBAPIConnection(),
        pool_size=PROD_POOL_KWARGS["pool_size"],
        max_overflow=PROD_POOL_KWARGS["max_overflow"],
        pre_ping=False,
    )
    engine = _FakeEngine(pool)

    assert read_pool_stats(engine)["capacity"] == 20

    held = []
    try:
        # 9 connexions : l'ancienne formule affichait déjà 90 % (seuil page !)
        # parce que overflow() vaut encore -1 à ce stade.
        for _ in range(9):
            held.append(pool.connect())
        stats = read_pool_stats(engine)
        assert stats["checked_out"] == 9
        assert stats["usage_pct"] == 45.0
        assert stats["status"] == "ok"

        # Capacité réellement atteinte (20/20) ⇒ là, et seulement là, saturated.
        for _ in range(11):
            held.append(pool.connect())
        stats = read_pool_stats(engine)
        assert stats["checked_out"] == 20
        assert stats["usage_pct"] == 100.0
        assert stats["status"] == "saturated"
    finally:
        for conn in held:
            conn.close()
        pool.dispose()


def test_read_pool_stats_nullpool_returns_none_fields():
    """NullPool (dev) n'expose pas size()/checkedout() ⇒ champs None, pas de usage_pct."""
    stats = read_pool_stats(_FakeEngine(object()))
    assert stats["status"] == "ok"
    assert stats["size"] is None
    assert stats["checked_out"] is None
    assert "usage_pct" not in stats


@pytest.fixture(autouse=True)
def _reset_pool_streak():
    """Le streak warn est un état module-level : on le remet à 0 par test."""
    from app.workers import scheduler as scheduler_mod

    scheduler_mod._pool_warn_streak = 0
    yield
    scheduler_mod._pool_warn_streak = 0


@pytest.mark.asyncio
async def test_pool_probe_warn_only_when_sustained():
    """Seuil warn (>=70 %) : une seule sonde ne lève PAS d'alerte ; deux
    sondes consécutives ⇒ warning structlog + capture_message Sentry.
    """
    from app.workers import scheduler as scheduler_mod

    fake_stats = {"status": "ok", "size": 10, "checked_out": 7, "usage_pct": 75.0}
    fake_sentry = MagicMock()
    with (
        patch("app.observability.pool_stats.read_pool_stats", return_value=fake_stats),
        patch.dict("sys.modules", {"sentry_sdk": fake_sentry}),
        patch.object(scheduler_mod, "settings") as mock_settings,
        patch.object(scheduler_mod, "logger") as mock_logger,
    ):
        mock_settings.pool_warn_threshold_pct = 70
        mock_settings.pool_page_threshold_pct = 90
        mock_settings.pool_warn_sustained_probes = 2

        # 1ʳᵉ sonde : franchit le seuil mais pas encore soutenu → pas d'alerte.
        await scheduler_mod._pool_health_probe()
        mock_logger.warning.assert_not_called()
        fake_sentry.capture_message.assert_not_called()
        assert mock_logger.info.call_args.kwargs.get("warn_pending") is True

        # 2ᵉ sonde consécutive : soutenu → warning + Sentry warning.
        await scheduler_mod._pool_health_probe()

    assert mock_logger.warning.call_args.args[0] == "db_pool_pressure_high"
    assert mock_logger.warning.call_args.kwargs["sustained_probes"] == 2
    fake_sentry.capture_message.assert_called_once()
    assert fake_sentry.capture_message.call_args.kwargs["level"] == "warning"


@pytest.mark.asyncio
async def test_pool_probe_pages_immediately_above_page_threshold():
    """Seuil page (>=90 %) : alerte Sentry level=fatal dès la 1ʳᵉ sonde,
    sans attendre la fenêtre "soutenu".
    """
    from app.workers import scheduler as scheduler_mod

    fake_stats = {
        "status": "saturated",
        "size": 10,
        "checked_out": 20,
        "usage_pct": 100.0,
    }
    fake_sentry = MagicMock()
    with (
        patch("app.observability.pool_stats.read_pool_stats", return_value=fake_stats),
        patch.dict("sys.modules", {"sentry_sdk": fake_sentry}),
        patch.object(scheduler_mod, "settings") as mock_settings,
        patch.object(scheduler_mod, "logger") as mock_logger,
    ):
        mock_settings.pool_warn_threshold_pct = 70
        mock_settings.pool_page_threshold_pct = 90
        mock_settings.pool_warn_sustained_probes = 2
        scheduler_mod._pool_warn_streak = 0
        await scheduler_mod._pool_health_probe()

    assert mock_logger.error.call_args.args[0] == "db_pool_pressure_critical"
    fake_sentry.capture_message.assert_called_once()
    assert fake_sentry.capture_message.call_args.kwargs["level"] == "fatal"


@pytest.mark.asyncio
async def test_pool_probe_quiet_below_threshold_resets_streak():
    """usage_pct < warn ⇒ info db_pool_probe, aucun warning ni Sentry, et le
    streak est remis à zéro (un retour sous le seuil casse le "soutenu").
    """
    from app.workers import scheduler as scheduler_mod

    fake_stats = {"status": "ok", "size": 10, "checked_out": 3, "usage_pct": 30.0}
    fake_sentry = MagicMock()
    with (
        patch("app.observability.pool_stats.read_pool_stats", return_value=fake_stats),
        patch.dict("sys.modules", {"sentry_sdk": fake_sentry}),
        patch.object(scheduler_mod, "settings") as mock_settings,
        patch.object(scheduler_mod, "logger") as mock_logger,
    ):
        mock_settings.pool_warn_threshold_pct = 70
        mock_settings.pool_page_threshold_pct = 90
        mock_settings.pool_warn_sustained_probes = 2
        scheduler_mod._pool_warn_streak = 1  # une sonde chaude précédente
        await scheduler_mod._pool_health_probe()

    assert scheduler_mod._pool_warn_streak == 0
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
