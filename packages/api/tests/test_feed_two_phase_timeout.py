"""Regression test for the default-feed two-phase timeout fallback.

Cf. docs/bugs/bug-feed-default-hang.md.

The `_use_two_phase` branch of `RecommendationService._get_candidates` fires
on the default feed view (no filter, followed sources present). Under a bad
SQL plan it could hang indefinitely and starve mobile clients. We now
`asyncio.wait_for` the query and degrade to a curated-only fallback on
timeout so the client never sees an infinite spinner.
"""

import asyncio
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4

import pytest

from app.services import recommendation_service as rs_module
from app.services.recommendation_service import RecommendationService


@pytest.mark.asyncio
async def test_two_phase_timeout_triggers_curated_fallback():
    """If the followed-sources query hangs, a curated fallback query runs
    and the caller gets a result instead of blocking forever."""

    session = MagicMock()
    session.rollback = AsyncMock()

    fallback_result = MagicMock()
    fallback_result.all.return_value = []

    calls = {"n": 0}

    async def _scalars(_stmt):
        calls["n"] += 1
        if calls["n"] == 1:
            # Two-phase query — simulate a hang well above the patched
            # timeout. wait_for should cancel us and the service should
            # rollback + issue the fallback query.
            await asyncio.sleep(60)
            raise AssertionError("two-phase coroutine should have been cancelled")
        return fallback_result

    session.scalars = _scalars

    service = RecommendationService(session)

    # Shrink the production timeout so the test runs in <1s.
    with patch.object(rs_module, "_FEED_TWO_PHASE_TIMEOUT_S", 0.05):
        candidates = await asyncio.wait_for(
            service._get_candidates(
                user_id=uuid4(),
                limit_candidates=500,
                followed_source_ids={uuid4()},
            ),
            # Outer guard: a regression (no wait_for in the service)
            # would otherwise hang CI for the full asyncio.sleep duration.
            timeout=5.0,
        )

    assert calls["n"] == 2, "curated fallback query must be executed on timeout"
    session.rollback.assert_awaited_once()
    assert candidates == []


@pytest.mark.asyncio
async def test_two_phase_happy_path_does_not_rollback():
    """When the two-phase query returns in time, no fallback, no rollback."""

    session = MagicMock()
    session.rollback = AsyncMock()

    ok_result = MagicMock()
    ok_result.all.return_value = []

    calls = {"n": 0}

    async def _scalars(_stmt):
        calls["n"] += 1
        return ok_result

    session.scalars = _scalars

    service = RecommendationService(session)

    candidates = await asyncio.wait_for(
        service._get_candidates(
            user_id=uuid4(),
            limit_candidates=500,
            followed_source_ids={uuid4()},
        ),
        timeout=5.0,
    )

    assert calls["n"] == 1, "happy path must not execute a fallback query"
    session.rollback.assert_not_awaited()
    assert candidates == []
