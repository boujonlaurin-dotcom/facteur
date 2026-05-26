"""Tests pour SubscriptionService — transitions de status, idempotence, PostHog."""

from datetime import datetime, timedelta
from unittest.mock import MagicMock, patch
from uuid import uuid4

import pytest

from app.models.subscription import UserSubscription
from app.services.subscription_service import SubscriptionService


def _make_event(
    event_type: str,
    event_id: str = "evt_1",
    product_id: str = "facteur_premium_monthly",
    period_type: str = "NORMAL",
    expiration_ms: int | None = None,
    original_app_user_id: str | None = "rc_user_1",
) -> dict:
    if expiration_ms is None:
        expiration_ms = int(
            (datetime.utcnow() + timedelta(days=30)).timestamp() * 1000
        )
    return {
        "id": event_id,
        "type": event_type,
        "product_id": product_id,
        "period_type": period_type,
        "expiration_at_ms": expiration_ms,
        "original_app_user_id": original_app_user_id,
    }


@pytest.mark.asyncio
async def test_get_or_create_creates_when_absent(db_session):
    service = SubscriptionService(db_session)
    user_id = str(uuid4())

    sub = await service._get_or_create_subscription(user_id)

    assert sub is not None
    assert sub.status == "trial"
    assert sub.trial_end > datetime.utcnow()


@pytest.mark.asyncio
async def test_initial_purchase_trial_sets_status_trial(db_session):
    service = SubscriptionService(db_session)
    user_id = str(uuid4())
    event = _make_event("INITIAL_PURCHASE", period_type="TRIAL")

    with patch.object(service, "_emit") as emit:
        await service.handle_initial_purchase(user_id, event)
        emit.assert_called_once()
        assert emit.call_args.args[1] == "trial_started"

    sub = await service._get_subscription(user_id)
    assert sub.status == "trial"
    assert sub.product_id == "facteur_premium_monthly"
    assert sub.last_event_id == "evt_1"


@pytest.mark.asyncio
async def test_initial_purchase_normal_sets_status_active(db_session):
    service = SubscriptionService(db_session)
    user_id = str(uuid4())
    event = _make_event("INITIAL_PURCHASE", period_type="NORMAL")

    with patch.object(service, "_emit") as emit:
        await service.handle_initial_purchase(user_id, event)
        emit.assert_called_once()
        assert emit.call_args.args[1] == "subscription_activated"

    sub = await service._get_subscription(user_id)
    assert sub.status == "active"


@pytest.mark.asyncio
async def test_renewal_after_trial_emits_activated(db_session):
    service = SubscriptionService(db_session)
    user_id = str(uuid4())
    # Pré-condition : user en trial
    await service._create_trial(user_id)

    with patch.object(service, "_emit") as emit:
        await service.handle_renewal(user_id, _make_event("RENEWAL", event_id="evt_r1"))
        emit.assert_called_once()
        assert emit.call_args.args[1] == "subscription_activated"

    sub = await service._get_subscription(user_id)
    assert sub.status == "active"


@pytest.mark.asyncio
async def test_renewal_on_active_emits_renewed(db_session):
    service = SubscriptionService(db_session)
    user_id = str(uuid4())
    sub = await service._create_trial(user_id)
    sub.status = "active"
    await db_session.flush()

    with patch.object(service, "_emit") as emit:
        await service.handle_renewal(user_id, _make_event("RENEWAL", event_id="evt_r2"))
        assert emit.call_args.args[1] == "subscription_renewed"


@pytest.mark.asyncio
async def test_cancellation_sets_status(db_session):
    service = SubscriptionService(db_session)
    user_id = str(uuid4())
    await service._create_trial(user_id)

    with patch.object(service, "_emit") as emit:
        await service.handle_cancellation(
            user_id, _make_event("CANCELLATION", event_id="evt_c1")
        )
        assert emit.call_args.args[1] == "subscription_cancelled"

    sub = await service._get_subscription(user_id)
    assert sub.status == "cancelled"


@pytest.mark.asyncio
async def test_expiration_sets_status(db_session):
    service = SubscriptionService(db_session)
    user_id = str(uuid4())
    await service._create_trial(user_id)

    await service.handle_expiration(
        user_id, _make_event("EXPIRATION", event_id="evt_e1")
    )

    sub = await service._get_subscription(user_id)
    assert sub.status == "expired"


@pytest.mark.asyncio
async def test_idempotence_same_event_id_skipped(db_session):
    service = SubscriptionService(db_session)
    user_id = str(uuid4())
    event = _make_event("INITIAL_PURCHASE", event_id="evt_same")

    with patch.object(service, "_emit") as emit:
        await service.handle_initial_purchase(user_id, event)
        first_call_count = emit.call_count
        # Rejeu identique → skip silencieux
        await service.handle_initial_purchase(user_id, event)
        assert emit.call_count == first_call_count


@pytest.mark.asyncio
async def test_product_change_updates_product_id(db_session):
    service = SubscriptionService(db_session)
    user_id = str(uuid4())
    await service._create_trial(user_id)

    event = {
        "id": "evt_pc1",
        "type": "PRODUCT_CHANGE",
        "new_product_id": "facteur_premium_annual",
        "expiration_at_ms": int(
            (datetime.utcnow() + timedelta(days=365)).timestamp() * 1000
        ),
    }
    await service.handle_product_change(user_id, event)

    sub = await service._get_subscription(user_id)
    assert sub.product_id == "facteur_premium_annual"


@pytest.mark.asyncio
async def test_uncancellation_reactivates(db_session):
    service = SubscriptionService(db_session)
    user_id = str(uuid4())
    sub = await service._create_trial(user_id)
    sub.status = "cancelled"
    await db_session.flush()

    await service.handle_uncancellation(
        user_id, _make_event("UNCANCELLATION", event_id="evt_u1")
    )

    sub = await service._get_subscription(user_id)
    assert sub.status == "active"
