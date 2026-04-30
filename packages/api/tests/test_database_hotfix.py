"""Tests pour le hot fix idle-in-tx zombies (incident 2026-04-28).

Couvre les 2 couches centralisées :
- Layer A : `safe_async_session` rollback() en finally même sur happy path.
- Layer B : connect_args contient `idle_in_transaction_session_timeout=60000`
  (filet Postgres-side).
"""

from unittest.mock import AsyncMock, patch

import pytest

from app import database


def test_connect_args_includes_idle_in_tx_timeout():
    """Régression : tout nouveau commit qui touche `connect_args` doit
    préserver le timeout côté Postgres. Sans ce SET, un site qui
    oublie le rollback() laisse des zombies indéfiniment dans
    Supavisor (cf. incident 2026-04-28).
    """
    import inspect

    src = inspect.getsource(database)
    assert "idle_in_transaction_session_timeout=60000" in src, (
        "connect_args must SET idle_in_transaction_session_timeout=60000 "
        "to prevent Supavisor zombies (incident 2026-04-28)"
    )
    assert "statement_timeout=30000" in src, "must keep statement_timeout"


@pytest.mark.asyncio
async def test_safe_async_session_rolls_back_on_happy_path():
    """Le pattern central : même sans exception, `safe_async_session`
    appelle rollback() en finally pour fermer toute tx implicite côté
    Supavisor. Sans ça, un SELECT read-only laisse le slot
    `idle in transaction`.
    """
    mock_session = AsyncMock()
    fake_factory_cm = AsyncMock()
    fake_factory_cm.__aenter__.return_value = mock_session
    fake_factory_cm.__aexit__.return_value = None

    with patch.object(database, "async_session_maker", return_value=fake_factory_cm):
        async with database.safe_async_session() as session:
            assert session is mock_session
            # No exception, no explicit commit — exactly the read-only pattern.

    mock_session.rollback.assert_awaited_once()


@pytest.mark.asyncio
async def test_safe_async_session_rolls_back_on_exception():
    """L'exception ne masque pas le rollback() — défense en profondeur."""
    mock_session = AsyncMock()
    fake_factory_cm = AsyncMock()
    fake_factory_cm.__aenter__.return_value = mock_session
    fake_factory_cm.__aexit__.return_value = None

    with patch.object(database, "async_session_maker", return_value=fake_factory_cm):
        with pytest.raises(RuntimeError):
            async with database.safe_async_session() as session:
                assert session is mock_session
                raise RuntimeError("simulated handler crash")

    mock_session.rollback.assert_awaited_once()


@pytest.mark.asyncio
async def test_safe_async_session_swallows_rollback_failure():
    """Si rollback() lui-même échoue (connexion morte), on log et
    on ne masque pas la sortie normale du context — sinon une simple
    déco DB tuerait toute la requête.
    """
    mock_session = AsyncMock()
    mock_session.rollback.side_effect = RuntimeError("connection already gone")
    fake_factory_cm = AsyncMock()
    fake_factory_cm.__aenter__.return_value = mock_session
    fake_factory_cm.__aexit__.return_value = None

    with patch.object(database, "async_session_maker", return_value=fake_factory_cm):
        async with database.safe_async_session() as session:
            assert session is mock_session

    mock_session.rollback.assert_awaited_once()


@pytest.mark.asyncio
async def test_safe_async_session_expunges_before_rollback_no_detached_error():
    """Régression critique 2026-04-28 PYTHON-2X (260+ events) :
    `await session.rollback()` en finally expirait tous les objets ORM
    persistants. Sites qui retournent un objet hors du `async with`
    (ex `_batch_personalization` → UserPersonalization) avaient
    `DetachedInstanceError` au prochain accès attribut → /api/feed 500.

    Fix : `expunge_all()` AVANT rollback. Garantit que :
    1. expunge_all est appelé (détache les objets, pas d'expiry par
       rollback ensuite).
    2. expunge_all est appelé AVANT rollback (ordre critique — l'inverse
       expirerait avant de détacher).
    3. rollback est toujours appelé (zombie defense intacte).
    """
    from unittest.mock import MagicMock

    call_order: list[str] = []
    mock_session = AsyncMock()
    mock_session.expunge_all = MagicMock(
        side_effect=lambda: call_order.append("expunge")
    )

    async def _track_rollback():
        call_order.append("rollback")

    mock_session.rollback = AsyncMock(side_effect=_track_rollback)

    fake_factory_cm = AsyncMock()
    fake_factory_cm.__aenter__.return_value = mock_session
    fake_factory_cm.__aexit__.return_value = None

    with patch.object(database, "async_session_maker", return_value=fake_factory_cm):
        async with database.safe_async_session() as session:
            assert session is mock_session

    mock_session.expunge_all.assert_called_once()
    mock_session.rollback.assert_awaited_once()
    # Ordre : expunge AVANT rollback. Sinon rollback expire ce qui reste
    # attaché → DetachedInstanceError à l'accès .relationship downstream.
    assert call_order == ["expunge", "rollback"], call_order


@pytest.mark.asyncio
async def test_safe_async_session_swallows_expunge_failure():
    """expunge_all() ne doit jamais bloquer le rollback derrière —
    sinon une session corrompue empêcherait le ROLLBACK SQL d'être
    envoyé → retour à zero des zombies.
    """
    from unittest.mock import MagicMock

    mock_session = AsyncMock()
    mock_session.expunge_all = MagicMock(side_effect=RuntimeError("session corrupted"))
    fake_factory_cm = AsyncMock()
    fake_factory_cm.__aenter__.return_value = mock_session
    fake_factory_cm.__aexit__.return_value = None

    with patch.object(database, "async_session_maker", return_value=fake_factory_cm):
        async with database.safe_async_session() as session:
            assert session is mock_session

    # rollback DOIT être appelé même si expunge a planté.
    mock_session.rollback.assert_awaited_once()
