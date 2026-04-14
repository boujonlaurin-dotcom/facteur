"""Tests for the global request-budget middleware.

Cf. docs/bugs/bug-infinite-load-requests.md. Last-resort defense against
"tout charge à l'infini" — every HTTP request is bounded by
`_REQUEST_BUDGET_S` seconds. Beyond that, the task is cancelled (which
releases its DB session) and a 503 `request_timeout` is returned.
"""

import asyncio

import pytest
from fastapi import APIRouter
from httpx import ASGITransport, AsyncClient

from app import main as main_mod
from app.main import app


@pytest.mark.asyncio
async def test_healthcheck_never_times_out(monkeypatch):
    """Health endpoints are exempt — must respond even when the budget is ~0."""
    monkeypatch.setattr(main_mod, "_REQUEST_BUDGET_S", 0.01)

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        resp = await ac.get("/api/health")

    assert resp.status_code == 200, (
        f"Expected 200, got {resp.status_code}: {resp.text[:200]}"
    )


@pytest.mark.asyncio
async def test_slow_endpoint_gets_503(monkeypatch):
    """A handler that sleeps past the budget must be cancelled and return 503.

    Guards against the prod symptom where a single hanging upstream holds a DB
    session and starves the pool. By cancelling the coroutine, the session
    context manager runs `finally`/`rollback` and the connection returns to
    the pool.
    """
    # Inject a deliberately slow route under /api/__test_slow.
    # Not prefixed with /api/health, so it is subject to the budget.
    test_router = APIRouter()

    @test_router.get("/__test_slow")
    async def _slow_route():
        await asyncio.sleep(5.0)  # Will exceed the tiny budget below.
        return {"ok": True}

    app.include_router(test_router, prefix="/api")
    monkeypatch.setattr(main_mod, "_REQUEST_BUDGET_S", 0.2)

    transport = ASGITransport(app=app)
    try:
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            resp = await ac.get("/api/__test_slow")
    finally:
        # Clean up: remove the injected route so it can't leak into other tests.
        app.router.routes = [
            r
            for r in app.router.routes
            if getattr(r, "path", None) != "/api/__test_slow"
        ]

    assert resp.status_code == 503, (
        f"Expected 503, got {resp.status_code}: {resp.text[:200]}"
    )
    body = resp.json()
    assert body["detail"] == "request_timeout"
    assert "budget_s" in body
