"""Tests for streak handler session scope and instrumentation (perf-watch 2026-04-20).

The /api/users/streak handler was reported holding its DB session ~60 s on a
trivial SELECT (Sentry "dbhandler exited" signature). Static analysis showed
the scope contains only DB awaits (no HTTP / sleep), so the fix is to
instrument `streak_handler_duration` and lock the contract: session released
promptly, log event emitted on every call.
"""

from datetime import date
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4

import pytest
from httpx import ASGITransport, AsyncClient

from app.database import get_db
from app.dependencies import get_current_user_id
from app.main import app
from app.schemas.streak import StreakResponse


def _canned_streak_response() -> StreakResponse:
    return StreakResponse(
        current_streak=3,
        longest_streak=5,
        last_activity_date=date(2026, 4, 19),
        weekly_count=2,
        weekly_goal=10,
        weekly_progress=0.2,
    )


def _build_fake_session() -> MagicMock:
    """A MagicMock session with async commit/rollback/close spies."""
    fake = MagicMock()
    fake.commit = AsyncMock()
    fake.rollback = AsyncMock()
    fake.close = AsyncMock()
    return fake


@pytest.mark.asyncio
async def test_users_streak_emits_duration_event():
    """Handler must emit `streak_handler_duration` with duration_ms and user_id."""
    fake_user_id = str(uuid4())
    fake_session = _build_fake_session()

    async def _fake_user():
        return fake_user_id

    async def _fake_db():
        try:
            yield fake_session
            await fake_session.commit()
        finally:
            await fake_session.close()

    app.dependency_overrides[get_current_user_id] = _fake_user
    app.dependency_overrides[get_db] = _fake_db

    try:
        with (
            patch("app.routers.users.StreakService") as MockService,
            patch("app.routers.users._perf_logger") as mock_logger,
        ):
            instance = MockService.return_value
            instance.get_streak = AsyncMock(return_value=_canned_streak_response())

            transport = ASGITransport(app=app)
            async with AsyncClient(transport=transport, base_url="http://test") as ac:
                resp = await ac.get("/api/users/streak")
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)
        app.dependency_overrides.pop(get_db, None)

    assert resp.status_code == 200
    body = resp.json()
    assert body["current_streak"] == 3
    assert body["weekly_goal"] == 10

    # Exactly one structured log event with the expected shape.
    assert mock_logger.info.call_count == 1
    call = mock_logger.info.call_args
    assert call.args == ("streak_handler_duration",)
    kwargs = call.kwargs
    assert kwargs["user_id"] == fake_user_id
    assert isinstance(kwargs["duration_ms"], (int, float))
    assert kwargs["duration_ms"] >= 0
    # Regression guard: no unexpected external await inflating the scope.
    assert kwargs["duration_ms"] < 1000


@pytest.mark.asyncio
async def test_users_streak_session_released_after_handler():
    """Handler must not hold the session: commit + close called once each."""
    fake_user_id = str(uuid4())
    fake_session = _build_fake_session()

    async def _fake_user():
        return fake_user_id

    async def _fake_db():
        try:
            yield fake_session
            await fake_session.commit()
        finally:
            await fake_session.close()

    app.dependency_overrides[get_current_user_id] = _fake_user
    app.dependency_overrides[get_db] = _fake_db

    try:
        with patch("app.routers.users.StreakService") as MockService:
            instance = MockService.return_value
            instance.get_streak = AsyncMock(return_value=_canned_streak_response())

            transport = ASGITransport(app=app)
            async with AsyncClient(transport=transport, base_url="http://test") as ac:
                resp = await ac.get("/api/users/streak")
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)
        app.dependency_overrides.pop(get_db, None)

    assert resp.status_code == 200
    fake_session.commit.assert_awaited_once()
    fake_session.close.assert_awaited_once()
    fake_session.rollback.assert_not_awaited()


@pytest.mark.asyncio
async def test_streaks_root_emits_duration_event():
    """The duplicate /api/streaks handler must emit the same instrumentation."""
    fake_user_id = str(uuid4())
    fake_session = _build_fake_session()

    async def _fake_user():
        return fake_user_id

    async def _fake_db():
        try:
            yield fake_session
            await fake_session.commit()
        finally:
            await fake_session.close()

    app.dependency_overrides[get_current_user_id] = _fake_user
    app.dependency_overrides[get_db] = _fake_db

    try:
        with (
            patch("app.routers.streaks.StreakService") as MockService,
            patch("app.routers.streaks._perf_logger") as mock_logger,
        ):
            instance = MockService.return_value
            instance.get_streak = AsyncMock(return_value=_canned_streak_response())

            transport = ASGITransport(app=app)
            async with AsyncClient(transport=transport, base_url="http://test") as ac:
                resp = await ac.get("/api/streaks")
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)
        app.dependency_overrides.pop(get_db, None)

    assert resp.status_code == 200
    assert mock_logger.info.call_count == 1
    call = mock_logger.info.call_args
    assert call.args == ("streak_handler_duration",)
    kwargs = call.kwargs
    assert kwargs["user_id"] == fake_user_id
    assert isinstance(kwargs["duration_ms"], (int, float))
    assert kwargs["duration_ms"] >= 0
    assert kwargs["duration_ms"] < 1000
    fake_session.commit.assert_awaited_once()
    fake_session.close.assert_awaited_once()
