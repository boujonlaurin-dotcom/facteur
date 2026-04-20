"""Regression tests for /digest/both singleflight dedup (hotfix P0 2026-04-20).

Without singleflight, a mobile client firing N concurrent /digest/both requests
for the same user would spawn N × 2 DB sessions via `asyncio.gather`, rapidly
saturating the pool. These tests lock in:

1. Same-user concurrent requests → only 1 leader runs the gather, followers
   share its result.
2. Different-user requests proceed in parallel (no false serialization).
3. If the leader fails (HTTPException), followers receive the same exception.
"""

import asyncio
import time
from unittest.mock import AsyncMock, patch
from uuid import uuid4

import pytest
from fastapi import HTTPException

from app.routers import digest as digest_router


class _FakeDB:
    """Minimal AsyncSession stand-in — the handler only calls `.scalar()` on it
    when `is_generation_running()` returns True (we stub that False here)."""

    async def scalar(self, *args, **kwargs):
        return None


@pytest.fixture(autouse=True)
def _reset_inflight():
    """Ensure a clean _inflight dict between tests."""
    digest_router._digest_both_inflight.clear()
    yield
    digest_router._digest_both_inflight.clear()


async def _call(user_uuid):
    return await digest_router.get_both_digests(
        target_date=None,
        db=_FakeDB(),
        current_user_id=str(user_uuid),
    )


@pytest.mark.asyncio
async def test_singleflight_same_user_dedupes_gather():
    """5 concurrent requests for the same user_uuid → `get_or_create_digest`
    is called only 2 times (1 leader × 2 variants), not 10."""

    user_uuid = uuid4()
    call_count = 0
    release = asyncio.Event()

    async def _slow_variant(*_args, **_kwargs):
        nonlocal call_count
        call_count += 1
        # Block until the followers have had a chance to arrive and join.
        await release.wait()
        return None  # None → handler returns 202, no DigestResponse needed

    with (
        patch.object(digest_router, "is_generation_running", return_value=False),
        patch.object(
            digest_router.DigestService,
            "get_or_create_digest",
            new=AsyncMock(side_effect=_slow_variant),
        ),
        patch.object(digest_router, "schedule_digest_regen"),
    ):
        # Fire 5 concurrent calls; let the event loop schedule them all before
        # releasing the leader so followers hit the singleflight lock first.
        tasks = [asyncio.create_task(_call(user_uuid)) for _ in range(5)]
        await asyncio.sleep(0.05)
        release.set()
        results = await asyncio.gather(*tasks)

    # Leader runs gather once → 2 variant calls (normal + serene). Followers
    # share the leader's future without re-entering _gen_variant.
    assert call_count == 2, (
        f"Expected 2 get_or_create_digest calls (1 leader × 2 variants), "
        f"got {call_count} — singleflight failed to dedupe."
    )
    # All 5 requests return the same response (JSONResponse 202).
    assert len(results) == 5
    assert all(r is results[0] for r in results[1:]), (
        "All followers should receive the exact same response object as the leader."
    )


@pytest.mark.asyncio
async def test_singleflight_different_users_run_in_parallel():
    """2 different user_uuids → 2 gathers run concurrently (no false serialization)."""

    user_a = uuid4()
    user_b = uuid4()
    variant_delay = 0.2

    async def _slow_variant(*_args, **_kwargs):
        await asyncio.sleep(variant_delay)
        return None

    with (
        patch.object(digest_router, "is_generation_running", return_value=False),
        patch.object(
            digest_router.DigestService,
            "get_or_create_digest",
            new=AsyncMock(side_effect=_slow_variant),
        ),
        patch.object(digest_router, "schedule_digest_regen"),
    ):
        t0 = time.monotonic()
        await asyncio.gather(_call(user_a), _call(user_b))
        elapsed = time.monotonic() - t0

    # If parallel: elapsed ≈ variant_delay. If serialized: ≈ 2 × variant_delay.
    # Generous margin — we only care that the second user is not blocked
    # behind the first.
    assert elapsed < variant_delay * 1.6, (
        f"Expected parallel execution (≈{variant_delay}s), got {elapsed:.3f}s — "
        f"different users should not serialize on the singleflight lock."
    )


@pytest.mark.asyncio
async def test_singleflight_leader_error_propagates_to_followers():
    """Leader raises HTTPException → all followers raise the same exception."""

    user_uuid = uuid4()
    release = asyncio.Event()

    async def _fail_after_wait(*_args, **_kwargs):
        await release.wait()
        raise HTTPException(status_code=503, detail="leader_failed")

    with (
        patch.object(digest_router, "is_generation_running", return_value=False),
        patch.object(
            digest_router.DigestService,
            "get_or_create_digest",
            new=AsyncMock(side_effect=_fail_after_wait),
        ),
        patch.object(digest_router, "schedule_digest_regen"),
    ):
        tasks = [asyncio.create_task(_call(user_uuid)) for _ in range(5)]
        await asyncio.sleep(0.05)
        release.set()
        results = await asyncio.gather(*tasks, return_exceptions=True)

    # All 5 must raise HTTPException(503). Leader raises from its own handler;
    # followers raise the same exception propagated via the shared future.
    assert len(results) == 5
    for idx, r in enumerate(results):
        assert isinstance(r, HTTPException), (
            f"Request {idx} should have raised HTTPException, got {type(r).__name__}: {r}"
        )
        assert r.status_code == 503, (
            f"Request {idx}: expected status 503, got {r.status_code}"
        )
