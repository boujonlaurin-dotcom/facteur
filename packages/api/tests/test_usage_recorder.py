"""Tests du recorder best-effort `record_api_call` (observabilité scaling WP-E).

Le recorder persiste 1 ligne dans `api_usage_events` par appel API externe.
Contrats critiques :
- kill-switch off ⇒ zéro insert ;
- ne lève JAMAIS, même si la session DB échoue (best-effort) ;
- call_site inconnu ⇒ warning mais insert quand même (on ne bloque pas) ;
- user_id en str ⇒ coercé en UUID.
"""

from contextlib import asynccontextmanager
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4

import pytest

from app.services.observability import usage_recorder
from app.services.observability.usage_recorder import record_api_call, track_api_call


def _make_session_maker(commit_side_effect=None):
    mock_session = MagicMock()
    mock_session.add = MagicMock()
    if commit_side_effect is not None:
        mock_session.commit = AsyncMock(side_effect=commit_side_effect)
    else:
        mock_session.commit = AsyncMock()

    @asynccontextmanager
    async def fake_sm(*args, **kwargs):
        yield mock_session

    return fake_sm, mock_session


def _settings(enabled=True):
    s = MagicMock()
    s.usage_tracking_enabled = enabled
    return s


@pytest.mark.asyncio
async def test_record_disabled_does_nothing():
    """Kill-switch off ⇒ aucune session ouverte, aucun insert."""
    fake_sm, mock_session = _make_session_maker()
    with (
        patch.object(
            usage_recorder, "get_settings", return_value=_settings(enabled=False)
        ),
        patch.object(
            usage_recorder,
            "safe_async_session",
            side_effect=lambda *_a, **_k: fake_sm(),
        ),
    ):
        await record_api_call(
            "mistral", "classification_pass1", model="mistral-small-latest"
        )

    mock_session.add.assert_not_called()
    mock_session.commit.assert_not_awaited()


@pytest.mark.asyncio
async def test_record_inserts_event_when_enabled():
    """Flag on ⇒ un ApiUsageEvent ajouté + commit, champs propagés."""
    fake_sm, mock_session = _make_session_maker()
    with (
        patch.object(usage_recorder, "get_settings", return_value=_settings()),
        patch.object(
            usage_recorder,
            "safe_async_session",
            side_effect=lambda *_a, **_k: fake_sm(),
        ),
    ):
        await record_api_call(
            "mistral",
            "classification_pass1",
            model="mistral-small-latest",
            status="ok",
            latency_ms=42,
        )

    mock_session.add.assert_called_once()
    event = mock_session.add.call_args.args[0]
    assert event.provider == "mistral"
    assert event.call_site == "classification_pass1"
    assert event.model == "mistral-small-latest"
    assert event.status == "ok"
    assert event.latency_ms == 42
    mock_session.commit.assert_awaited_once()


@pytest.mark.asyncio
async def test_record_never_raises_on_db_error():
    """Une erreur DB (commit) ne doit jamais remonter à l'appelant."""
    fake_sm, _ = _make_session_maker(commit_side_effect=RuntimeError("db down"))
    with (
        patch.object(usage_recorder, "get_settings", return_value=_settings()),
        patch.object(
            usage_recorder,
            "safe_async_session",
            side_effect=lambda *_a, **_k: fake_sm(),
        ),
        patch.object(usage_recorder, "logger") as mock_logger,
    ):
        await record_api_call("brave", "smart_search_brave")  # MUST NOT raise

    mock_logger.warning.assert_called_once()
    assert mock_logger.warning.call_args.args[0] == "usage_recorder.persist_failed"


@pytest.mark.asyncio
async def test_record_warns_on_unknown_call_site_but_still_inserts():
    """call_site hors enum ⇒ warning de typo, mais on enregistre quand même."""
    fake_sm, mock_session = _make_session_maker()
    with (
        patch.object(usage_recorder, "get_settings", return_value=_settings()),
        patch.object(
            usage_recorder,
            "safe_async_session",
            side_effect=lambda *_a, **_k: fake_sm(),
        ),
        patch.object(usage_recorder, "logger") as mock_logger,
    ):
        await record_api_call("mistral", "totally_made_up")

    mock_logger.warning.assert_any_call(
        "usage_recorder.unknown_call_site", call_site="totally_made_up"
    )
    mock_session.add.assert_called_once()


@pytest.mark.asyncio
async def test_record_coerces_string_user_id():
    """user_id en str valide ⇒ coercé en UUID sur l'event."""
    fake_sm, mock_session = _make_session_maker()
    uid = uuid4()
    with (
        patch.object(usage_recorder, "get_settings", return_value=_settings()),
        patch.object(
            usage_recorder,
            "safe_async_session",
            side_effect=lambda *_a, **_k: fake_sm(),
        ),
    ):
        await record_api_call("mistral", "editorial", user_id=str(uid))

    event = mock_session.add.call_args.args[0]
    assert event.user_id == uid


@pytest.mark.asyncio
async def test_record_bad_string_user_id_falls_back_to_none():
    """user_id en str non-UUID ⇒ None (jamais d'exception)."""
    fake_sm, mock_session = _make_session_maker()
    with (
        patch.object(usage_recorder, "get_settings", return_value=_settings()),
        patch.object(
            usage_recorder,
            "safe_async_session",
            side_effect=lambda *_a, **_k: fake_sm(),
        ),
    ):
        await record_api_call("mistral", "editorial", user_id="not-a-uuid")

    event = mock_session.add.call_args.args[0]
    assert event.user_id is None


@pytest.mark.asyncio
async def test_record_persists_token_counts():
    """prompt_tokens / completion_tokens sont portés sur l'ApiUsageEvent (LR-1)."""
    fake_sm, mock_session = _make_session_maker()
    with (
        patch.object(usage_recorder, "get_settings", return_value=_settings()),
        patch.object(
            usage_recorder,
            "safe_async_session",
            side_effect=lambda *_a, **_k: fake_sm(),
        ),
    ):
        await record_api_call(
            "mistral",
            "good_news_pass2",
            model="mistral-large-latest",
            prompt_tokens=1900,
            completion_tokens=42,
        )

    event = mock_session.add.call_args.args[0]
    assert event.prompt_tokens == 1900
    assert event.completion_tokens == 42


@pytest.mark.asyncio
async def test_track_api_call_propagates_tracker_tokens():
    """Le context manager remonte les tokens posés sur le tracker au recorder."""
    with patch.object(
        usage_recorder, "record_api_call", new_callable=AsyncMock
    ) as mock_record:
        async with track_api_call(
            "mistral", "classification_pass1", model="mistral-small-latest"
        ) as call:
            call.prompt_tokens = 1234
            call.completion_tokens = 56
            call.status = "ok"

    mock_record.assert_awaited_once()
    kwargs = mock_record.await_args.kwargs
    assert kwargs["prompt_tokens"] == 1234
    assert kwargs["completion_tokens"] == 56
    assert kwargs["status"] == "ok"


@pytest.mark.asyncio
async def test_track_api_call_tokens_default_none_on_failure():
    """Sans pose de tokens (échec avant réponse), ils restent None et le statut error."""
    with (
        patch.object(
            usage_recorder, "record_api_call", new_callable=AsyncMock
        ) as mock_record,
        pytest.raises(RuntimeError),
    ):
        async with track_api_call("mistral", "editorial"):
            raise RuntimeError("boom before response")

    kwargs = mock_record.await_args.kwargs
    assert kwargs["prompt_tokens"] is None
    assert kwargs["completion_tokens"] is None
    assert kwargs["status"] == "error"
