"""Tests pour POST /api/checkout/send-link."""

from unittest.mock import AsyncMock, patch
from uuid import uuid4

import pytest
from fastapi import FastAPI, HTTPException, status
from fastapi.testclient import TestClient

from app.database import get_db
from app.dependencies import get_current_user_id
from app.routers.checkout import router


def _make_client(db_session, user_id: str) -> TestClient:
    app = FastAPI()
    app.include_router(router, prefix="/api/checkout")
    app.dependency_overrides[get_db] = lambda: db_session
    app.dependency_overrides[get_current_user_id] = lambda: user_id
    return TestClient(app, raise_server_exceptions=False)


@pytest.mark.asyncio
async def test_send_link_happy_path(db_session):
    user_id = str(uuid4())
    send_mock = AsyncMock(return_value=None)

    with (
        patch(
            "app.routers.checkout._supabase_admin_get_user_email",
            new=AsyncMock(return_value="user@example.com"),
        ),
        patch("app.routers.checkout._supabase_send_magic_link", new=send_mock),
        _make_client(db_session, user_id) as client,
    ):
        resp = client.post("/api/checkout/send-link", json={})

    assert resp.status_code == 200
    body = resp.json()
    assert body["sent"] is True
    assert body["email"] == "user@example.com"

    # Le redirect_to du magic link est l'URL de checkout avec l'app_user_id.
    email_arg, redirect_arg = send_mock.await_args.args
    assert email_arg == "user@example.com"
    assert redirect_arg.startswith("https://pay.rev.cat/facteur-premium")
    assert f"app_user_id={user_id}" in redirect_arg


@pytest.mark.asyncio
async def test_send_link_founder_offering(db_session):
    user_id = str(uuid4())
    send_mock = AsyncMock(return_value=None)

    with (
        patch(
            "app.routers.checkout._supabase_admin_get_user_email",
            new=AsyncMock(return_value="user@example.com"),
        ),
        patch("app.routers.checkout._supabase_send_magic_link", new=send_mock),
        _make_client(db_session, user_id) as client,
    ):
        resp = client.post("/api/checkout/send-link", json={"offering": "founder"})

    assert resp.status_code == 200
    _, redirect_arg = send_mock.await_args.args
    assert redirect_arg.startswith("https://pay.rev.cat/facteur-founder")


@pytest.mark.asyncio
async def test_send_link_email_not_found(db_session):
    user_id = str(uuid4())

    with (
        patch(
            "app.routers.checkout._supabase_admin_get_user_email",
            new=AsyncMock(return_value=None),
        ),
        _make_client(db_session, user_id) as client,
    ):
        resp = client.post("/api/checkout/send-link", json={})

    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_send_link_rate_limited_propagates_429(db_session):
    user_id = str(uuid4())

    with (
        patch(
            "app.routers.checkout._supabase_admin_get_user_email",
            new=AsyncMock(return_value="user@example.com"),
        ),
        patch(
            "app.routers.checkout._supabase_send_magic_link",
            new=AsyncMock(
                side_effect=HTTPException(
                    status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                    detail="Magic link rate-limited, retry in a minute",
                )
            ),
        ),
        _make_client(db_session, user_id) as client,
    ):
        resp = client.post("/api/checkout/send-link", json={})

    assert resp.status_code == 429


@pytest.mark.asyncio
async def test_send_link_resend_flag_tracked(db_session):
    user_id = str(uuid4())
    posthog_mock = type("P", (), {"captured": None})()

    def capture(**kwargs):
        posthog_mock.captured = kwargs

    with (
        patch(
            "app.routers.checkout._supabase_admin_get_user_email",
            new=AsyncMock(return_value="user@example.com"),
        ),
        patch(
            "app.routers.checkout._supabase_send_magic_link",
            new=AsyncMock(return_value=None),
        ),
        patch("app.routers.checkout.get_posthog_client") as posthog_client,
    ):
        posthog_client.return_value.capture = capture
        with _make_client(db_session, user_id) as client:
            resp = client.post("/api/checkout/send-link", json={"resend": True})

    assert resp.status_code == 200
    assert posthog_mock.captured["event"] == "checkout_link_sent"
    assert posthog_mock.captured["properties"]["resend"] is True
