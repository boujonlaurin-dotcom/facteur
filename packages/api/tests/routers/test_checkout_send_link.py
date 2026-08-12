"""Contrat du CTA soutien : Resend direct, sans chemin OTP Supabase."""

from types import SimpleNamespace
from unittest.mock import AsyncMock, patch
from uuid import uuid4

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.database import get_db
from app.dependencies import CurrentUserIdentity, get_current_user_identity
from app.routers.checkout import router
from app.services.support_link_email import ResendSendResult


def _make_client(db_session, user_id: str) -> TestClient:
    app = FastAPI()
    app.include_router(router, prefix="/api/checkout")
    app.dependency_overrides[get_db] = lambda: db_session
    app.dependency_overrides[get_current_user_identity] = lambda: CurrentUserIdentity(
        user_id=user_id, email="user@example.com"
    )
    return TestClient(app, raise_server_exceptions=False)


@pytest.mark.asyncio
async def test_send_link_persists_resend_delivery_without_supabase_otp(db_session):
    user_id = str(uuid4())
    send = AsyncMock(return_value=ResendSendResult(message_id="resend-message-1"))
    settings = SimpleNamespace(support_link_delivery_enabled=True)

    with (
        patch("app.routers.checkout.get_settings", return_value=settings),
        patch("app.services.support_link_email.send_support_link_email", new=send),
        _make_client(db_session, user_id) as client,
    ):
        response = client.post("/api/checkout/send-link", json={})

    assert response.status_code == 202
    body = response.json()
    assert body["status"] == "accepted"
    assert body["delivery_id"]
    assert send.await_count == 1


@pytest.mark.asyncio
async def test_send_link_queues_temporary_resend_failure(db_session):
    user_id = str(uuid4())
    settings = SimpleNamespace(support_link_delivery_enabled=True)
    from app.services.support_link_email import ResendSendError

    with (
        patch("app.routers.checkout.get_settings", return_value=settings),
        patch(
            "app.services.support_link_email.send_support_link_email",
            new=AsyncMock(side_effect=ResendSendError("resend_timeout", temporary=True)),
        ),
        _make_client(db_session, user_id) as client,
    ):
        response = client.post("/api/checkout/send-link", json={})

    assert response.status_code == 202
    assert response.json()["status"] == "queued"


@pytest.mark.asyncio
async def test_send_link_requires_full_resend_configuration(db_session):
    with (
        patch(
            "app.routers.checkout.get_settings",
            return_value=SimpleNamespace(support_link_delivery_enabled=False),
        ),
        _make_client(db_session, str(uuid4())) as client,
    ):
        response = client.post("/api/checkout/send-link", json={})

    assert response.status_code == 503
