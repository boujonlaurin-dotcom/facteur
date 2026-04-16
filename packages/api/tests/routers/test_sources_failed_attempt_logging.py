"""Unit tests for the failed_source_attempt logging helper.

Regression against the bug documented in
`docs/maintenance/failed-sources-dataset.md` (Bug 2) : because
`get_db` rolls back on any BaseException — including the
HTTPException raised right after the `db.add(attempt)` — every
FailedSourceAttempt insert in the previous implementation was
silently discarded.

The fix uses its own short-lived session via `async_session_maker`
so the commit survives the handler's HTTPException.
"""

from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4

import pytest


@pytest.mark.asyncio
async def test_log_failed_source_attempt_uses_fresh_session_and_commits():
    """The helper must open its own session and commit before the caller
    raises — not rely on the request-scoped `get_db` session."""
    from app.routers import sources as sources_mod

    mock_session = MagicMock()
    mock_session.add = MagicMock()
    mock_session.commit = AsyncMock()

    mock_cm = MagicMock()
    mock_cm.__aenter__ = AsyncMock(return_value=mock_session)
    mock_cm.__aexit__ = AsyncMock(return_value=None)

    mock_session_maker = MagicMock(return_value=mock_cm)

    with patch.object(sources_mod, "async_session_maker", mock_session_maker):
        await sources_mod._log_failed_source_attempt(
            user_id=str(uuid4()),
            input_text="https://example.com/",
            input_type="url",
            endpoint="custom",
            error_message="boom",
        )

    assert mock_session_maker.called, "should open a fresh session, not reuse get_db"
    mock_session.add.assert_called_once()
    mock_session.commit.assert_awaited_once()


@pytest.mark.asyncio
async def test_log_failed_source_attempt_swallows_errors():
    """If the log write itself fails, the helper must not raise —
    we never want observability to break the user-facing 400."""
    from app.routers import sources as sources_mod

    broken_session_maker = MagicMock(side_effect=RuntimeError("DB down"))

    with patch.object(sources_mod, "async_session_maker", broken_session_maker):
        # Must not raise
        await sources_mod._log_failed_source_attempt(
            user_id=str(uuid4()),
            input_text="https://example.com/",
            input_type="url",
            endpoint="custom",
            error_message="boom",
        )


@pytest.mark.asyncio
async def test_log_failed_source_attempt_truncates_long_inputs():
    """Guard against pathological input overflowing the DB columns."""
    from app.routers import sources as sources_mod

    captured = {}
    mock_session = MagicMock()

    def _capture(obj):
        captured["obj"] = obj

    mock_session.add = MagicMock(side_effect=_capture)
    mock_session.commit = AsyncMock()

    mock_cm = MagicMock()
    mock_cm.__aenter__ = AsyncMock(return_value=mock_session)
    mock_cm.__aexit__ = AsyncMock(return_value=None)

    with patch.object(
        sources_mod, "async_session_maker", MagicMock(return_value=mock_cm)
    ):
        await sources_mod._log_failed_source_attempt(
            user_id=str(uuid4()),
            input_text="x" * 5000,
            input_type="url",
            endpoint="custom",
            error_message="y" * 5000,
        )

    attempt = captured["obj"]
    assert len(attempt.input_text) == 500
    assert len(attempt.error_message) == 1000
