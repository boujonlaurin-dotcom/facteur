"""Tests for /api/health/pool — DB pool observability endpoint.

Cf. docs/bugs/bug-infinite-load-requests.md. This endpoint exposes pool
saturation so on-call can diagnose "requests loading indefinitely" in one
click. It must:
- Stay unauth (remain usable when the rest of the API is wedged).
- Never leak user data — only aggregated pool metrics.
- Return a `status` field that flips to "saturated" when the pool is full.
"""

import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app


@pytest.mark.asyncio
async def test_pool_endpoint_returns_metrics():
    """`GET /api/health/pool` must return 200 with pool metrics."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        resp = await ac.get("/api/health/pool")

    assert resp.status_code == 200, (
        f"Expected 200, got {resp.status_code}: {resp.text[:200]}"
    )
    body = resp.json()
    # Required fields — locked in so dashboards/alerts can depend on them.
    assert "status" in body
    assert body["status"] in ("ok", "saturated")
    assert "pool_class" in body
    # Usage pct is only computed when size is known (QueuePool); in tests we
    # use NullPool which has no size, so it may be None.
    assert body.get("size") is None or isinstance(body["size"], int)


def test_prod_pool_kwargs_capacity():
    """Locks the production pool capacity at 25+25=50 with fail-fast timeout.

    Supabase Pooler is 60 conns shared — bumping these without leaving
    headroom for the in-process scheduler will starve other clients.
    """
    from app.database import PROD_POOL_KWARGS

    assert PROD_POOL_KWARGS["pool_size"] == 25
    assert PROD_POOL_KWARGS["max_overflow"] == 25
    assert PROD_POOL_KWARGS["pool_timeout"] == 10
    assert PROD_POOL_KWARGS["pool_recycle"] == 180
