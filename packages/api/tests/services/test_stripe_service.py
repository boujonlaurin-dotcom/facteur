"""Tests du service Stripe : bornes montant, args session, construct_event."""

from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import pytest
import stripe
from fastapi import HTTPException

from app.config import get_settings
from app.services.stripe_service import (
    construct_event,
    create_support_subscription_session,
)


@pytest.fixture
def stripe_configured(monkeypatch):
    monkeypatch.setattr(get_settings(), "stripe_secret_key", "sk_test_123")
    monkeypatch.setattr(get_settings(), "stripe_support_product_id", "prod_abc")
    monkeypatch.setattr(get_settings(), "stripe_currency", "eur")
    monkeypatch.setattr(get_settings(), "stripe_support_min_cents", 200)
    monkeypatch.setattr(get_settings(), "stripe_support_max_cents", 10000)
    monkeypatch.setattr(get_settings(), "public_web_base_url", "https://facteur.app")


@pytest.mark.asyncio
async def test_create_session_passes_expected_args(stripe_configured):
    fake_create = MagicMock(
        return_value=SimpleNamespace(url="https://checkout.stripe.com/x")
    )
    with patch.object(stripe.checkout.Session, "create", fake_create):
        url = await create_support_subscription_session("user-1", "a@b.co", 500)

    assert url == "https://checkout.stripe.com/x"
    kwargs = fake_create.call_args.kwargs
    assert kwargs["mode"] == "subscription"
    assert kwargs["client_reference_id"] == "user-1"
    assert kwargs["customer_email"] == "a@b.co"
    price_data = kwargs["line_items"][0]["price_data"]
    assert price_data["currency"] == "eur"
    assert price_data["product"] == "prod_abc"
    assert price_data["unit_amount"] == 500
    assert price_data["recurring"] == {"interval": "month"}
    assert kwargs["subscription_data"]["metadata"]["user_id"] == "user-1"
    assert kwargs["metadata"]["user_id"] == "user-1"
    assert "{CHECKOUT_SESSION_ID}" in kwargs["success_url"]
    assert kwargs["idempotency_key"]  # présent


@pytest.mark.asyncio
async def test_amount_below_min_rejected(stripe_configured):
    with pytest.raises(HTTPException) as exc:
        await create_support_subscription_session("u", "a@b.co", 199)
    assert exc.value.status_code == 400


@pytest.mark.asyncio
async def test_amount_above_max_rejected(stripe_configured):
    with pytest.raises(HTTPException) as exc:
        await create_support_subscription_session("u", "a@b.co", 10001)
    assert exc.value.status_code == 400


@pytest.mark.asyncio
async def test_503_when_stripe_not_configured(monkeypatch):
    monkeypatch.setattr(get_settings(), "stripe_secret_key", "")
    with pytest.raises(HTTPException) as exc:
        await create_support_subscription_session("u", "a@b.co", 500)
    assert exc.value.status_code == 503


def test_construct_event_valid(monkeypatch):
    monkeypatch.setattr(get_settings(), "stripe_webhook_secret", "whsec_x")
    fake_event = {"id": "evt_1", "type": "invoice.paid", "data": {"object": {}}}
    with patch.object(
        stripe.Webhook, "construct_event", MagicMock(return_value=fake_event)
    ):
        assert construct_event(b"{}", "sig") == fake_event


def test_construct_event_invalid_signature_401(monkeypatch):
    monkeypatch.setattr(get_settings(), "stripe_webhook_secret", "whsec_x")
    err = stripe.error.SignatureVerificationError("bad sig", "sig-header")
    with (
        patch.object(stripe.Webhook, "construct_event", MagicMock(side_effect=err)),
        pytest.raises(HTTPException) as exc,
    ):
        construct_event(b"{}", "bad")
    assert exc.value.status_code == 401


def test_construct_event_503_when_not_configured(monkeypatch):
    monkeypatch.setattr(get_settings(), "stripe_webhook_secret", "")
    with pytest.raises(HTTPException) as exc:
        construct_event(b"{}", "sig")
    assert exc.value.status_code == 503


@pytest.mark.asyncio
async def test_message_carried_in_session_metadata(stripe_configured):
    fake_create = MagicMock(
        return_value=SimpleNamespace(url="https://checkout.stripe.com/x")
    )
    with patch.object(stripe.checkout.Session, "create", fake_create):
        await create_support_subscription_session(
            "user-1", "a@b.co", 500, message="  Bravo pour le projet  "
        )
    md = fake_create.call_args.kwargs["metadata"]
    assert md["support_message"] == "Bravo pour le projet"  # trim appliqué


@pytest.mark.asyncio
async def test_blank_message_omitted_from_metadata(stripe_configured):
    fake_create = MagicMock(return_value=SimpleNamespace(url="u"))
    with patch.object(stripe.checkout.Session, "create", fake_create):
        await create_support_subscription_session(
            "user-1", "a@b.co", 500, message="   "
        )
    assert "support_message" not in fake_create.call_args.kwargs["metadata"]
