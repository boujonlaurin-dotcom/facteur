"""Tests for the migration-drift guard on /api/health/ready.

Incident 2026-07-14 : la migration `cv01` (colonne `sources.coverage_themes`)
n'avait jamais été appliquée sur la DB partagée. Tout `select(Source)` renvoyait
500, mais /api/health (liveness) restait 200 et l'ancien /api/health/ready
(un simple `SELECT 1`) aussi → Railway continuait de router du trafic vers un
conteneur en drift. Ce garde-fou sort un conteneur en retard de schéma du load
balancer (503), **sans** casser prod pendant la fenêtre expand-contract (DB en
avance sur l'ancien code prod → doit rester ready).
"""

from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from httpx import ASGITransport, AsyncClient

from app.checks import (
    MultipleAlembicHeadsError,
    _single_head,
    check_migrations_up_to_date,
    get_migration_readiness,
)
from app.database import get_db
from app.main import app


def _fake_engine(current_rev: str | None, *, raise_on_connect: bool = False):
    """Build a mock engine whose `connect()` yields a conn returning current_rev."""

    class _FakeConn:
        async def run_sync(self, _fn):
            return current_rev

    class _FakeConnectCtx:
        async def __aenter__(self):
            if raise_on_connect:
                raise RuntimeError("db down")
            return _FakeConn()

        async def __aexit__(self, *_a):
            return False

    engine = MagicMock()
    engine.connect.return_value = _FakeConnectCtx()
    return engine


# --- Unit: direction-aware decision -------------------------------------------


@pytest.mark.asyncio
async def test_behind_true_when_current_is_strict_ancestor():
    """The incident case: DB at ue01, code head at me01 → behind=True."""
    head = "me01_media_eval_tables"
    ancestors = frozenset(
        {head, "cv01_source_coverage_themes", "ue01_user_entity_affinity"}
    )
    with (
        patch("app.checks._code_head_and_ancestors", return_value=(head, ancestors)),
        patch("app.checks.engine", _fake_engine("ue01_user_entity_affinity")),
    ):
        status = await get_migration_readiness()
    assert status["behind"] is True
    assert status["head"] == head
    assert status["current"] == "ue01_user_entity_affinity"


@pytest.mark.asyncio
async def test_behind_false_when_current_equals_head():
    head = "me01_media_eval_tables"
    ancestors = frozenset({head, "cv01_source_coverage_themes"})
    with (
        patch("app.checks._code_head_and_ancestors", return_value=(head, ancestors)),
        patch("app.checks.engine", _fake_engine(head)),
    ):
        status = await get_migration_readiness()
    assert status["behind"] is False


@pytest.mark.asyncio
async def test_behind_false_when_db_ahead_of_code_expand_contract():
    """Expand-contract window: prod runs OLD code (head=cv01) on a DB already
    advanced by staging (current=me01, NOT an ancestor of cv01). Must stay ready
    — 503-ing here would take prod down every weekly cycle."""
    head = "cv01_source_coverage_themes"
    ancestors = frozenset({head, "ue01_user_entity_affinity"})  # me01 absent
    with (
        patch("app.checks._code_head_and_ancestors", return_value=(head, ancestors)),
        patch("app.checks.engine", _fake_engine("me01_media_eval_tables")),
    ):
        status = await get_migration_readiness()
    assert status["behind"] is False


@pytest.mark.asyncio
async def test_fail_open_on_db_error():
    head = "me01_media_eval_tables"
    ancestors = frozenset({head})
    with (
        patch("app.checks._code_head_and_ancestors", return_value=(head, ancestors)),
        patch("app.checks.engine", _fake_engine(None, raise_on_connect=True)),
    ):
        status = await get_migration_readiness()
    assert status["behind"] is False


@pytest.mark.asyncio
async def test_fail_open_on_config_error():
    with patch(
        "app.checks._code_head_and_ancestors",
        side_effect=RuntimeError("no alembic.ini"),
    ):
        status = await get_migration_readiness()
    assert status["behind"] is False


# --- Fork Alembic (incident 2026-07-25) ---------------------------------------


def _script_dir(*heads: str):
    script_directory = MagicMock()
    script_directory.get_heads.return_value = list(heads)
    return script_directory


def test_single_head_returns_the_head():
    assert _single_head(_script_dir("mg04_merge_pt01_rd01")) == "mg04_merge_pt01_rd01"


def test_single_head_returns_none_when_no_revision():
    assert _single_head(_script_dir()) is None


def test_single_head_raises_on_fork():
    """`heads[0]` masquait le fork : selon l'ordre, le boot passait au vert avec
    une révision jamais appliquée → 500 généralisés, readiness verte."""
    with pytest.raises(MultipleAlembicHeadsError, match="pt01"):
        _single_head(
            _script_dir("pt01_contents_entities_trgm", "rd01_ucs_completed_at")
        )


@pytest.mark.asyncio
async def test_readiness_not_ready_on_fork():
    """Le fail-open ne s'applique pas au fork : l'image ne peut pas migrer."""
    with patch(
        "app.checks._code_head_and_ancestors",
        side_effect=MultipleAlembicHeadsError("Multiple Alembic heads: ['a', 'b']"),
    ):
        status = await get_migration_readiness()
    assert status["behind"] is True


@pytest.mark.asyncio
async def test_startup_check_crashes_on_fork(monkeypatch):
    """Le contrôle de démarrage est fatal sur un fork, comme sur un schéma en retard."""
    monkeypatch.setenv("DATABASE_URL", "postgresql://unused")
    with (
        patch(
            "app.checks.script.ScriptDirectory.from_config",
            return_value=_script_dir(
                "pt01_contents_entities_trgm", "rd01_ucs_completed_at"
            ),
        ),
        pytest.raises(MultipleAlembicHeadsError),
    ):
        await check_migrations_up_to_date()


# --- Endpoint: 503 vs 200 -----------------------------------------------------


async def _override_db_ok():
    session = MagicMock()
    session.execute = AsyncMock()  # SELECT 1 succeeds
    yield session


@pytest.mark.asyncio
async def test_readiness_returns_503_on_migration_drift():
    app.dependency_overrides[get_db] = _override_db_ok
    try:
        with patch(
            "app.checks.get_migration_readiness",
            AsyncMock(
                return_value={
                    "behind": True,
                    "head": "me01_media_eval_tables",
                    "current": "ue01_user_entity_affinity",
                }
            ),
        ):
            transport = ASGITransport(app=app)
            async with AsyncClient(transport=transport, base_url="http://test") as ac:
                resp = await ac.get("/api/health/ready")
    finally:
        app.dependency_overrides.pop(get_db, None)

    assert resp.status_code == 503
    body = resp.json()
    assert body["status"] == "not_ready"
    assert body["migrations"] == "pending"
    assert body["migration_current"] == "ue01_user_entity_affinity"
    assert body["migration_head"] == "me01_media_eval_tables"


@pytest.mark.asyncio
async def test_readiness_returns_200_when_up_to_date():
    app.dependency_overrides[get_db] = _override_db_ok
    try:
        with patch(
            "app.checks.get_migration_readiness",
            AsyncMock(
                return_value={
                    "behind": False,
                    "head": "me01_media_eval_tables",
                    "current": "me01_media_eval_tables",
                }
            ),
        ):
            transport = ASGITransport(app=app)
            async with AsyncClient(transport=transport, base_url="http://test") as ac:
                resp = await ac.get("/api/health/ready")
    finally:
        app.dependency_overrides.pop(get_db, None)

    assert resp.status_code == 200
    assert resp.json()["status"] == "ready"
