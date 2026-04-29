"""Tests pour SET LOCAL timeouts pushed dans chaque session.

Suite à l'investigation 2026-04-28 : `connect_args.options="-c idle_in_tx..."`
est ignoré par Supavisor en mode transaction pooling. Solution durable :
pousser SET LOCAL en SQL au début de chaque tx — Supavisor transit les
SQL commands transparente.
"""

from unittest.mock import AsyncMock, patch

import pytest

from app import database


@pytest.mark.asyncio
async def test_safe_async_session_emits_set_local_default_timeouts():
    """Default : statement_timeout=30s, idle_in_tx=10s sur chaque session."""
    mock_session = AsyncMock()
    fake_factory_cm = AsyncMock()
    fake_factory_cm.__aenter__.return_value = mock_session
    fake_factory_cm.__aexit__.return_value = None

    with patch.object(database, "async_session_maker", return_value=fake_factory_cm):
        async with database.safe_async_session() as session:
            assert session is mock_session

    # 2 SET LOCAL + (potential downstream code calls) — assert at minimum the SETs.
    sql_calls = [
        str(call.args[0]) for call in mock_session.execute.await_args_list
    ]
    assert any("SET LOCAL statement_timeout = 30000" in s for s in sql_calls), sql_calls
    assert any(
        "SET LOCAL idle_in_transaction_session_timeout = 10000" in s for s in sql_calls
    ), sql_calls
    mock_session.rollback.assert_awaited_once()


@pytest.mark.asyncio
async def test_safe_async_session_accepts_custom_timeouts():
    """Le hot path /api/feed pousse 8s/5s — défense en profondeur stricte."""
    mock_session = AsyncMock()
    fake_factory_cm = AsyncMock()
    fake_factory_cm.__aenter__.return_value = mock_session
    fake_factory_cm.__aexit__.return_value = None

    with patch.object(database, "async_session_maker", return_value=fake_factory_cm):
        async with database.safe_async_session(
            statement_timeout_ms=8_000, idle_in_tx_timeout_ms=5_000
        ) as _:
            pass

    sql_calls = [str(c.args[0]) for c in mock_session.execute.await_args_list]
    assert any("SET LOCAL statement_timeout = 8000" in s for s in sql_calls), sql_calls
    assert any(
        "SET LOCAL idle_in_transaction_session_timeout = 5000" in s for s in sql_calls
    ), sql_calls


@pytest.mark.asyncio
async def test_safe_async_session_swallows_set_local_failure():
    """Si le SET LOCAL échoue (DB down), on ne doit pas planter la requête —
    la connexion morte sera évacuée par handle_error.
    """
    mock_session = AsyncMock()
    mock_session.execute.side_effect = RuntimeError("connection lost")
    fake_factory_cm = AsyncMock()
    fake_factory_cm.__aenter__.return_value = mock_session
    fake_factory_cm.__aexit__.return_value = None

    with patch.object(database, "async_session_maker", return_value=fake_factory_cm):
        async with database.safe_async_session() as session:
            assert session is mock_session  # MUST yield, MUST NOT raise


def test_feed_batch_sessions_use_strict_timeouts():
    """Régression : les 4 sessions ad-hoc du hot path /api/feed doivent
    pousser des timeouts stricts (8s/5s) — pas les défauts (30s/10s).
    Trop laxiste = pool saturé avant que Postgres ne tue.
    """
    import inspect

    from app.services import recommendation_service

    src = inspect.getsource(recommendation_service)
    # 4 sites attendus (cf. fix 2026-04-28) : _batch_personalization,
    # custom_topics, _batch_scoring_context, _batch_impressions.
    strict_call = (
        "safe_async_session(\n"
        "                statement_timeout_ms=8_000, idle_in_tx_timeout_ms=5_000\n"
        "            )"
    )
    assert src.count("statement_timeout_ms=8_000") >= 4, (
        f"Expected ≥4 strict timeouts in feed hot path, found "
        f"{src.count('statement_timeout_ms=8_000')}. Did you remove a feed "
        f"batch session without keeping the strict timeout?"
    )
    assert strict_call in src, (
        "Strict-timeout safe_async_session() call signature changed — update "
        "this test or check the feed batch sessions"
    )
