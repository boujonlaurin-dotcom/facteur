"""Round 6 — tests for `_enrich_community_carousel` rollback behaviour.

Same anti-pattern as PYTHON-14 (community.get_community_recommendations) : a
fail-open handler that swallows `Exception` without rolling back leaves the
injected SQLAlchemy session dirty. get_db's final commit then raises
PendingRollbackError, which escapes as a 500.

`_enrich_community_carousel` is called from both `/api/digest` and
`/api/digest/both`. It uses the `db` session injected by `get_db`. If any DB
call inside raises (PgBouncer kill, listener didn't match signature), the
session must be rolled back before the handler returns.

Fix mirrors D3 (PR #437 community.py) : explicit `await db.rollback()` guarded
by `try/except` so a failing rollback does not break the fail-open contract.
"""

from datetime import date, datetime, timezone
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4

import pytest

from app.routers.digest import _enrich_community_carousel
from app.schemas.digest import DigestResponse


def _make_digest_response() -> DigestResponse:
    """Minimal DigestResponse shape for the enrichment call."""
    return DigestResponse(
        digest_id=uuid4(),
        user_id=uuid4(),
        target_date=date(2026, 4, 19),
        generated_at=datetime(2026, 4, 19, 6, 0, 0, tzinfo=timezone.utc),
        items=[],
        is_completed=False,
        completed_at=None,
    )


@pytest.mark.asyncio
async def test_enrich_rolls_back_on_service_exception():
    """When CommunityRecommendationService raises (simulated PgBouncer kill),
    the enrichment MUST call db.rollback() before returning the digest
    unchanged."""
    digest = _make_digest_response()

    fake_session = MagicMock()
    fake_session.rollback = AsyncMock()
    fake_session.execute = AsyncMock()

    with patch(
        "app.routers.digest.CommunityRecommendationService"
    ) as MockService:
        instance = MockService.return_value
        instance.get_recent_recommendations = AsyncMock(
            side_effect=RuntimeError("boom — simulated pgbouncer kill")
        )

        result = await _enrich_community_carousel(fake_session, uuid4(), digest)

    # Fail-open : digest returned unchanged (no carousel populated).
    assert result is digest
    # Default factory = empty list (no enrichment happened).
    assert result.community_carousel == []

    # Critical : rollback called exactly once to clean the session.
    fake_session.rollback.assert_awaited_once()


@pytest.mark.asyncio
async def test_enrich_stays_fail_open_even_if_rollback_raises():
    """If db.rollback() itself raises (connection already dead), the
    enrichment MUST still return the digest unchanged instead of
    propagating the exception."""
    digest = _make_digest_response()

    fake_session = MagicMock()
    fake_session.rollback = AsyncMock(
        side_effect=RuntimeError("rollback failed — connection is closed")
    )
    fake_session.execute = AsyncMock()

    with patch(
        "app.routers.digest.CommunityRecommendationService"
    ) as MockService:
        instance = MockService.return_value
        instance.get_recent_recommendations = AsyncMock(
            side_effect=RuntimeError("boom — simulated pgbouncer kill")
        )

        result = await _enrich_community_carousel(fake_session, uuid4(), digest)

    # Still fail-open.
    assert result is digest
    # Default factory = empty list (no enrichment happened).
    assert result.community_carousel == []
    # rollback was attempted, its own failure swallowed.
    fake_session.rollback.assert_awaited_once()


@pytest.mark.asyncio
async def test_enrich_nominal_empty_does_not_rollback():
    """Regression guard : when the service returns 0 items, enrichment
    short-circuits and MUST NOT call rollback (would be a pointless
    roundtrip in the happy path)."""
    digest = _make_digest_response()

    fake_session = MagicMock()
    fake_session.rollback = AsyncMock()
    fake_session.execute = AsyncMock()

    with patch(
        "app.routers.digest.CommunityRecommendationService"
    ) as MockService:
        instance = MockService.return_value
        instance.get_recent_recommendations = AsyncMock(return_value=[])

        result = await _enrich_community_carousel(fake_session, uuid4(), digest)

    assert result is digest
    # Nominal path — no rollback.
    fake_session.rollback.assert_not_awaited()
