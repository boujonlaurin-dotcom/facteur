"""Tests for community recommendations handler rollback behaviour (PYTHON-14).

Context : when `CommunityRecommendationService.get_community_carousels` (or
any DB call inside the handler) raises because Supabase/PgBouncer killed the
connection with a signature not matched by `_invalidate_on_supabase_kill`,
SQLAlchemy flags the session as dirty. The handler swallows the exception
(fail-open contract : mobile must never see a 500 on this optional surface),
so `get_db` never sees the exception and therefore never rolls back — the
next query on the same session then raises `PendingRollbackError`, which is
exactly what Sentry PYTHON-14 showed 14× on 3 users on 2026-04-18.

Fix : call `await db.rollback()` explicitly inside the `except` block, itself
guarded by a `try/except` so that a failing rollback (connection already dead)
does not break the fail-open contract.
"""

from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4

import pytest
from httpx import ASGITransport, AsyncClient

from app.database import get_db
from app.dependencies import get_current_user_id
from app.main import app


@pytest.mark.asyncio
async def test_handler_rolls_back_on_service_exception():
    """When the service raises, the handler MUST call db.rollback() before
    returning an empty fail-open response."""
    fake_user_id = str(uuid4())

    fake_session = MagicMock()
    fake_session.rollback = AsyncMock()
    # execute should never be reached because the service raises first,
    # but set it up defensively.
    fake_session.execute = AsyncMock()

    async def _fake_user():
        return fake_user_id

    async def _fake_db():
        yield fake_session

    app.dependency_overrides[get_current_user_id] = _fake_user
    app.dependency_overrides[get_db] = _fake_db

    try:
        with patch(
            "app.routers.community.CommunityRecommendationService"
        ) as MockService:
            instance = MockService.return_value
            instance.get_community_carousels = AsyncMock(
                side_effect=RuntimeError("boom — simulated pgbouncer kill")
            )

            transport = ASGITransport(app=app)
            async with AsyncClient(transport=transport, base_url="http://test") as ac:
                resp = await ac.get("/api/community/recommendations")
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)
        app.dependency_overrides.pop(get_db, None)

    # Fail-open : empty body, 200
    assert resp.status_code == 200
    body = resp.json()
    assert body == {"feed_carousel": [], "digest_carousel": []}

    # The critical assertion : rollback must have been called exactly once.
    fake_session.rollback.assert_awaited_once()


@pytest.mark.asyncio
async def test_handler_stays_fail_open_even_if_rollback_itself_raises():
    """If db.rollback() itself raises (connection already fully dead), the
    handler MUST still return an empty response instead of propagating."""
    fake_user_id = str(uuid4())

    fake_session = MagicMock()
    fake_session.rollback = AsyncMock(
        side_effect=RuntimeError("rollback failed — connection is closed")
    )
    fake_session.execute = AsyncMock()

    async def _fake_user():
        return fake_user_id

    async def _fake_db():
        yield fake_session

    app.dependency_overrides[get_current_user_id] = _fake_user
    app.dependency_overrides[get_db] = _fake_db

    try:
        with patch(
            "app.routers.community.CommunityRecommendationService"
        ) as MockService:
            instance = MockService.return_value
            instance.get_community_carousels = AsyncMock(
                side_effect=RuntimeError("boom — simulated pgbouncer kill")
            )

            transport = ASGITransport(app=app)
            async with AsyncClient(transport=transport, base_url="http://test") as ac:
                resp = await ac.get("/api/community/recommendations")
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)
        app.dependency_overrides.pop(get_db, None)

    # Still 200, still empty — rollback failure is swallowed.
    assert resp.status_code == 200
    body = resp.json()
    assert body == {"feed_carousel": [], "digest_carousel": []}
    fake_session.rollback.assert_awaited_once()


@pytest.mark.asyncio
async def test_handler_nominal_case_does_not_rollback():
    """Regression guard : when everything works, the handler returns real
    carousels and does NOT call rollback (would be a pointless roundtrip)."""
    fake_user_id = str(uuid4())

    fake_session = MagicMock()
    fake_session.rollback = AsyncMock()

    # For the UserContentStatus lookup branch: return an empty scalars list.
    mock_exec_result = MagicMock()
    scalars = MagicMock()
    scalars.all = MagicMock(return_value=[])
    mock_exec_result.scalars = MagicMock(return_value=scalars)
    fake_session.execute = AsyncMock(return_value=mock_exec_result)

    async def _fake_user():
        return fake_user_id

    async def _fake_db():
        yield fake_session

    app.dependency_overrides[get_current_user_id] = _fake_user
    app.dependency_overrides[get_db] = _fake_db

    try:
        with patch(
            "app.routers.community.CommunityRecommendationService"
        ) as MockService:
            instance = MockService.return_value
            # No items — simplest nominal shape that exercises the success path.
            instance.get_community_carousels = AsyncMock(return_value=([], []))

            transport = ASGITransport(app=app)
            async with AsyncClient(transport=transport, base_url="http://test") as ac:
                resp = await ac.get("/api/community/recommendations")
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)
        app.dependency_overrides.pop(get_db, None)

    assert resp.status_code == 200
    body = resp.json()
    assert body == {"feed_carousel": [], "digest_carousel": []}
    # Critical : nominal path never rolls back.
    fake_session.rollback.assert_not_awaited()
