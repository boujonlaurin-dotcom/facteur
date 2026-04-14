"""Regression tests for the `/digest/both` hang protection.

Cf. docs/bugs/bug-infinite-load-requests.md.

Without the `asyncio.wait_for` wrapper around the parallel digest generation,
a slow upstream (Mistral LLM, Google News RSS, Supabase) could hang the
request forever, hold 2 DB sessions, and rapidly exhaust the pool — making
*every* other endpoint appear to "load indefinitely".

These tests lock in:
1. A variant that takes longer than the configured timeout → 503.
2. The 503 body carries `detail == "digest_generation_timeout"` so the
   mobile client can distinguish it from generic 503 and bound its retries.
"""

import asyncio
from unittest.mock import AsyncMock, patch
from uuid import uuid4

import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app


async def _hang_forever(*_args, **_kwargs):
    """Stub that never resolves — simulates an upstream hang."""
    await asyncio.sleep(3600)


@pytest.mark.asyncio
async def test_digest_both_hanging_variant_returns_503_timeout():
    """If `get_or_create_digest` hangs, the endpoint must return 503 within
    the configured gather timeout — not block indefinitely."""

    # Bypass auth + DB dependencies for this router-level regression test.
    from app.database import get_db
    from app.dependencies import get_current_user_id

    fake_user_id = str(uuid4())

    async def _fake_user():
        return fake_user_id

    class _FakeDB:
        async def scalar(self, *args, **kwargs):
            return None  # No pending batch run, no existing digest

    async def _fake_db():
        yield _FakeDB()

    app.dependency_overrides[get_current_user_id] = _fake_user
    app.dependency_overrides[get_db] = _fake_db

    # Shrink the timeout so the test is fast — we only care about the
    # *behavior* (503 on timeout), not the exact 30 s production value.
    try:
        with (
            patch("app.routers.digest.DIGEST_BOTH_VARIANT_TIMEOUT_S", 0.2),
            patch("app.routers.digest.DIGEST_BOTH_GATHER_TIMEOUT_S", 0.3),
            patch(
                "app.routers.digest.is_generation_running", return_value=False
            ),
            patch(
                "app.routers.digest.DigestService.get_or_create_digest",
                new=AsyncMock(side_effect=_hang_forever),
            ),
        ):
            transport = ASGITransport(app=app)
            async with AsyncClient(
                transport=transport, base_url="http://test", timeout=10.0
            ) as ac:
                # Wrap in wait_for so a regression (no timeout) fails the
                # test quickly instead of hanging CI for 5 min.
                resp = await asyncio.wait_for(
                    ac.get("/api/digest/both"), timeout=5.0
                )
    finally:
        app.dependency_overrides.clear()

    assert resp.status_code == 503, (
        f"Expected 503 on upstream hang, got {resp.status_code}. "
        f"Body: {resp.text[:200]}"
    )
    body = resp.json()
    assert body.get("detail") == "digest_generation_timeout", (
        "503 body must carry `detail: digest_generation_timeout` so the "
        "mobile client can distinguish it from generic failures. "
        f"Got: {body}"
    )
