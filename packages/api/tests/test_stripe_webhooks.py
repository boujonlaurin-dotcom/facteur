"""Tests du webhook Stripe : signature, dispatch, mapping DB, grant/revoke,
idempotence (event rejoué -> pas de double grant)."""

from datetime import UTC, datetime, timedelta
from unittest.mock import AsyncMock, patch
from uuid import UUID, uuid4

import pytest
from fastapi import HTTPException
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select

from app.database import get_db
from app.main import app
from app.models.subscription import (
    StripeEvent,
    SupporterMessage,
    UserSubscription,
)


def _period_end_seconds(days: int = 30) -> int:
    return int((datetime.now(UTC) + timedelta(days=days)).timestamp())


async def _post_event(event: dict):
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        return await ac.post(
            "/api/webhooks/stripe",
            content=b"{}",
            headers={"Stripe-Signature": "sig"},
        )


@pytest.fixture
def override_db(db_session):
    async def _db():
        yield db_session

    app.dependency_overrides[get_db] = _db
    try:
        yield db_session
    finally:
        app.dependency_overrides.pop(get_db, None)


@pytest.fixture
def grant_mocks(monkeypatch):
    grant = AsyncMock()
    revoke = AsyncMock()
    monkeypatch.setattr(
        "app.services.subscription_service.RevenueCatGrantService.grant_premium",
        grant,
    )
    monkeypatch.setattr(
        "app.services.subscription_service.RevenueCatGrantService.revoke_premium",
        revoke,
    )
    return grant, revoke


def _patch_construct(event: dict):
    return patch("app.routers.stripe_webhooks.construct_event", return_value=event)


@pytest.mark.asyncio
async def test_invalid_signature_returns_401(override_db):
    with patch(
        "app.routers.stripe_webhooks.construct_event",
        side_effect=HTTPException(status_code=401, detail="Invalid Stripe signature"),
    ):
        resp = await _post_event({})
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_checkout_completed_persists_mapping(override_db, grant_mocks):
    user_id = str(uuid4())
    event = {
        "id": "evt_checkout_1",
        "type": "checkout.session.completed",
        "data": {
            "object": {
                "client_reference_id": user_id,
                "customer": "cus_1",
                "subscription": "sub_1",
                "metadata": {"user_id": user_id, "support_amount_cents": "500"},
                "amount_total": 500,
            }
        },
    }
    with _patch_construct(event):
        resp = await _post_event(event)
    assert resp.status_code == 200

    row = (
        await override_db.execute(
            select(UserSubscription).where(UserSubscription.user_id == UUID(user_id))
        )
    ).scalar_one()
    assert row.provider == "stripe"
    assert row.stripe_customer_id == "cus_1"
    assert row.stripe_subscription_id == "sub_1"
    assert row.support_amount_cents == 500


@pytest.mark.asyncio
async def test_invoice_paid_activates_and_grants(override_db, grant_mocks):
    grant, _revoke = grant_mocks
    user_id = str(uuid4())
    end_s = _period_end_seconds(30)
    event = {
        "id": "evt_invoice_1",
        "type": "invoice.paid",
        "data": {
            "object": {
                "subscription": "sub_1",
                "customer": "cus_1",
                "period_start": _period_end_seconds(0),
                "lines": {"data": [{"period": {"end": end_s}}]},
                "subscription_details": {"metadata": {"user_id": user_id}},
            }
        },
    }
    with _patch_construct(event):
        resp = await _post_event(event)
    assert resp.status_code == 200

    row = (
        await override_db.execute(
            select(UserSubscription).where(UserSubscription.user_id == UUID(user_id))
        )
    ).scalar_one()
    assert row.status == "active"
    assert row.provider == "stripe"

    grant.assert_awaited_once()
    called_user, called_end_ms = grant.await_args.args
    assert called_user == user_id
    # end_time_ms = period_end + 3 j de grâce
    expected_ms = int((end_s + 3 * 86400) * 1000)
    assert abs(called_end_ms - expected_ms) < 2000


@pytest.mark.asyncio
async def test_duplicate_event_grants_only_once(override_db, grant_mocks):
    grant, _revoke = grant_mocks
    user_id = str(uuid4())
    end_s = _period_end_seconds(30)
    event = {
        "id": "evt_invoice_dup",
        "type": "invoice.paid",
        "data": {
            "object": {
                "subscription": "sub_dup",
                "customer": "cus_dup",
                "lines": {"data": [{"period": {"end": end_s}}]},
                "subscription_details": {"metadata": {"user_id": user_id}},
            }
        },
    }
    with _patch_construct(event):
        first = await _post_event(event)
        second = await _post_event(event)

    assert first.status_code == 200
    assert first.json()["status"] == "processed"
    assert second.status_code == 200
    assert second.json()["status"] == "duplicate"
    grant.assert_awaited_once()

    # une seule ligne d'idempotence enregistrée
    events = (
        (
            await override_db.execute(
                select(StripeEvent).where(StripeEvent.event_id == "evt_invoice_dup")
            )
        )
        .scalars()
        .all()
    )
    assert len(events) == 1


@pytest.mark.asyncio
async def test_subscription_deleted_revokes(override_db, grant_mocks):
    _grant, revoke = grant_mocks
    user_id = str(uuid4())
    # pré-crée la ligne miroir (comme après checkout.session.completed)
    override_db.add(
        UserSubscription(
            id=uuid4(),
            user_id=UUID(user_id),
            status="active",
            provider="stripe",
            stripe_subscription_id="sub_del",
            stripe_customer_id="cus_del",
            trial_end=datetime.utcnow() + timedelta(days=1),
        )
    )
    await override_db.flush()

    event = {
        "id": "evt_sub_deleted",
        "type": "customer.subscription.deleted",
        "data": {
            "object": {
                "id": "sub_del",
                "customer": "cus_del",
                "metadata": {"user_id": user_id},
            }
        },
    }
    with _patch_construct(event):
        resp = await _post_event(event)
    assert resp.status_code == 200

    revoke.assert_awaited_once_with(user_id)
    row = (
        await override_db.execute(
            select(UserSubscription).where(UserSubscription.user_id == UUID(user_id))
        )
    ).scalar_one()
    assert row.status == "cancelled"


@pytest.mark.asyncio
async def test_checkout_completed_persists_message_unpublished(override_db, grant_mocks):
    user_id = str(uuid4())
    event = {
        "id": "evt_checkout_msg",
        "type": "checkout.session.completed",
        "data": {
            "object": {
                "id": "cs_msg_1",
                "client_reference_id": user_id,
                "customer": "cus_m",
                "subscription": "sub_m",
                "metadata": {
                    "user_id": user_id,
                    "support_amount_cents": "500",
                    "support_message": "Merci pour ce projet.",
                },
            }
        },
    }
    with _patch_construct(event):
        resp = await _post_event(event)
    assert resp.status_code == 200

    msg = (
        await override_db.execute(
            select(SupporterMessage).where(SupporterMessage.user_id == UUID(user_id))
        )
    ).scalar_one()
    assert msg.message == "Merci pour ce projet."
    assert msg.published is False
    assert msg.stripe_session_id == "cs_msg_1"


@pytest.mark.asyncio
async def test_checkout_completed_without_message_stores_none(override_db, grant_mocks):
    user_id = str(uuid4())
    event = {
        "id": "evt_checkout_nomsg",
        "type": "checkout.session.completed",
        "data": {
            "object": {
                "id": "cs_nomsg",
                "client_reference_id": user_id,
                "metadata": {"user_id": user_id, "support_amount_cents": "300"},
            }
        },
    }
    with _patch_construct(event):
        await _post_event(event)

    rows = (
        await override_db.execute(
            select(SupporterMessage).where(SupporterMessage.user_id == UUID(user_id))
        )
    ).scalars().all()
    assert rows == []


@pytest.mark.asyncio
async def test_support_messages_endpoint_returns_only_published(override_db):
    override_db.add_all(
        [
            SupporterMessage(
                id=uuid4(),
                message="visible",
                published=True,
                created_at=datetime.now(UTC),
            ),
            SupporterMessage(
                id=uuid4(),
                message="en attente de modération",
                published=False,
                created_at=datetime.now(UTC),
            ),
        ]
    )
    await override_db.flush()

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        resp = await ac.get("/api/checkout/support-messages")

    assert resp.status_code == 200
    messages = [m["message"] for m in resp.json()]
    assert "visible" in messages
    assert "en attente de modération" not in messages


@pytest.mark.asyncio
async def test_payment_failed_sets_past_due(override_db, grant_mocks):
    user_id = str(uuid4())
    override_db.add(
        UserSubscription(
            id=uuid4(),
            user_id=UUID(user_id),
            status="active",
            provider="stripe",
            stripe_subscription_id="sub_pf",
            stripe_customer_id="cus_pf",
            trial_end=datetime.utcnow() + timedelta(days=1),
        )
    )
    await override_db.flush()

    event = {
        "id": "evt_payment_failed",
        "type": "invoice.payment_failed",
        "data": {"object": {"subscription": "sub_pf", "customer": "cus_pf"}},
    }
    with _patch_construct(event):
        resp = await _post_event(event)
    assert resp.status_code == 200

    row = (
        await override_db.execute(
            select(UserSubscription).where(UserSubscription.user_id == UUID(user_id))
        )
    ).scalar_one()
    assert row.status == "past_due"
