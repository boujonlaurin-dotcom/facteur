"""Tests pour le webhook RevenueCat — signature, idempotence, dispatch."""

import hashlib
import hmac
import json
from unittest.mock import AsyncMock, patch
from uuid import uuid4

import pytest

from app.routers.webhooks import verify_revenuecat_signature


def test_verify_signature_hmac_valid():
    secret = "topsecret"
    payload = b'{"event":{"type":"INITIAL_PURCHASE"}}'
    signature = hmac.new(secret.encode(), payload, hashlib.sha256).hexdigest()
    assert verify_revenuecat_signature(payload, signature, secret) is True


def test_verify_signature_hmac_invalid():
    secret = "topsecret"
    payload = b'{"event":{"type":"INITIAL_PURCHASE"}}'
    assert verify_revenuecat_signature(payload, "deadbeef", secret) is False


def test_verify_signature_bearer_valid():
    secret = "topsecret"
    payload = b'{}'
    assert (
        verify_revenuecat_signature(payload, f"Bearer {secret}", secret) is True
    )


def test_verify_signature_bearer_invalid():
    assert verify_revenuecat_signature(b'{}', "Bearer wrongsecret", "right") is False


@pytest.mark.asyncio
async def test_webhook_dispatches_initial_purchase(db_session):
    """Le webhook route vers handle_initial_purchase quand type=INITIAL_PURCHASE."""
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from app.database import get_db
    from app.routers.webhooks import router

    app = FastAPI()
    app.include_router(router, prefix="/api/webhooks")
    app.dependency_overrides[get_db] = lambda: db_session

    user_id = str(uuid4())
    payload = {
        "event": {
            "id": "evt_test_1",
            "type": "INITIAL_PURCHASE",
            "app_user_id": user_id,
            "product_id": "facteur_premium_monthly",
            "period_type": "TRIAL",
            "expiration_at_ms": 9999999999000,
        }
    }

    with patch(
        "app.services.subscription_service.SubscriptionService.handle_initial_purchase",
        new=AsyncMock(),
    ) as mock_handler:
        with TestClient(app) as client:
            resp = client.post(
                "/api/webhooks/revenuecat",
                content=json.dumps(payload),
                headers={"Content-Type": "application/json"},
            )
        assert resp.status_code == 200
        mock_handler.assert_awaited_once()
        assert mock_handler.await_args.args[0] == user_id


@pytest.mark.asyncio
async def test_webhook_ignores_missing_app_user_id(db_session):
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from app.database import get_db
    from app.routers.webhooks import router

    app = FastAPI()
    app.include_router(router, prefix="/api/webhooks")
    app.dependency_overrides[get_db] = lambda: db_session

    with TestClient(app) as client:
        resp = client.post(
            "/api/webhooks/revenuecat",
            json={"event": {"type": "INITIAL_PURCHASE"}},
        )
    assert resp.status_code == 200
    assert resp.json()["status"] == "ignored"


@pytest.mark.asyncio
async def test_webhook_returns_200_for_unknown_event_type(db_session):
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from app.database import get_db
    from app.routers.webhooks import router

    app = FastAPI()
    app.include_router(router, prefix="/api/webhooks")
    app.dependency_overrides[get_db] = lambda: db_session

    with TestClient(app) as client:
        resp = client.post(
            "/api/webhooks/revenuecat",
            json={
                "event": {
                    "id": "evt_test_x",
                    "type": "SOME_FUTURE_EVENT",
                    "app_user_id": str(uuid4()),
                }
            },
        )
    assert resp.status_code == 200
    assert resp.json()["status"] == "processed"
