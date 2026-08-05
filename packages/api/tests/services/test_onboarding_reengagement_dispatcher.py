"""Tests du dispatcher de relance des abandons d'onboarding (J+0 / J+1)."""

from datetime import UTC, datetime, timedelta
from unittest.mock import Mock, patch
from uuid import uuid4

import pytest
from sqlalchemy import select

from app.models.analytics import AnalyticsEvent
from app.models.push_notification import PushDelivery, PushDevice
from app.models.user import UserProfile
from app.services.onboarding_reengagement_dispatcher import (
    KIND_D0,
    KIND_D1,
    dispatch_onboarding_reengagement_pushes,
)


async def _seed_abandoner(
    db_session,
    *,
    created_at: datetime,
    timezone: str = "Europe/Paris",
    onboarding_completed: bool = False,
):
    user_id = uuid4()
    device_id = uuid4()
    db_session.add(
        UserProfile(
            user_id=user_id,
            display_name="Abandoner",
            onboarding_completed=onboarding_completed,
        )
    )
    await db_session.flush()
    db_session.add(
        PushDevice(
            device_id=device_id,
            user_id=user_id,
            fcm_token="reengage-token",
            platform="android",
            timezone=timezone,
            created_at=created_at,
            last_active_at=created_at,
        )
    )
    await db_session.commit()
    return user_id, device_id


def _sync(sender: Mock):
    def _call(*args):
        return sender(*args)

    return _call


# 11:00 Paris (heure active, hors quiet hours) le 15/06/2026 = 09:00 UTC.
_ACTIVE_NOW = datetime(2026, 6, 15, 9, 0, tzinfo=UTC)


@pytest.mark.asyncio
async def test_d0_sent_after_one_hour_when_incomplete(db_session, fake_session_maker):
    _, device_id = await _seed_abandoner(
        db_session, created_at=_ACTIVE_NOW - timedelta(minutes=90)
    )
    sender = Mock(return_value="message-id")

    with patch(
        "app.services.onboarding_reengagement_dispatcher.safe_async_session",
        fake_session_maker,
    ):
        metrics = await dispatch_onboarding_reengagement_pushes(
            now=_ACTIVE_NOW, sender=_sync(sender)
        )

    assert metrics["sent"] == 1
    assert sender.call_count == 1
    _, title, _, data = sender.call_args.args
    assert data["kind"] == KIND_D0
    assert data["route"] == "/onboarding"
    delivery = await db_session.scalar(
        select(PushDelivery).where(
            PushDelivery.device_id == device_id, PushDelivery.kind == KIND_D0
        )
    )
    assert delivery is not None
    assert delivery.status == "sent"


@pytest.mark.asyncio
async def test_nothing_before_one_hour(db_session, fake_session_maker):
    await _seed_abandoner(db_session, created_at=_ACTIVE_NOW - timedelta(minutes=30))
    sender = Mock(return_value="message-id")

    with patch(
        "app.services.onboarding_reengagement_dispatcher.safe_async_session",
        fake_session_maker,
    ):
        metrics = await dispatch_onboarding_reengagement_pushes(
            now=_ACTIVE_NOW, sender=_sync(sender)
        )

    assert metrics["sent"] == 0
    assert sender.call_count == 0


@pytest.mark.asyncio
async def test_idempotent_across_runs(db_session, fake_session_maker):
    await _seed_abandoner(db_session, created_at=_ACTIVE_NOW - timedelta(minutes=90))
    sender = Mock(return_value="message-id")

    with patch(
        "app.services.onboarding_reengagement_dispatcher.safe_async_session",
        fake_session_maker,
    ):
        first = await dispatch_onboarding_reengagement_pushes(
            now=_ACTIVE_NOW, sender=_sync(sender)
        )
        second = await dispatch_onboarding_reengagement_pushes(
            now=_ACTIVE_NOW + timedelta(minutes=5), sender=_sync(sender)
        )

    assert first["sent"] == 1
    assert second["sent"] == 0
    assert sender.call_count == 1


@pytest.mark.asyncio
async def test_completed_user_excluded(db_session, fake_session_maker):
    await _seed_abandoner(
        db_session,
        created_at=_ACTIVE_NOW - timedelta(minutes=90),
        onboarding_completed=True,
    )
    sender = Mock(return_value="message-id")

    with patch(
        "app.services.onboarding_reengagement_dispatcher.safe_async_session",
        fake_session_maker,
    ):
        metrics = await dispatch_onboarding_reengagement_pushes(
            now=_ACTIVE_NOW, sender=_sync(sender)
        )

    assert metrics["sent"] == 0
    assert sender.call_count == 0


@pytest.mark.asyncio
async def test_stop_on_complete_no_d1(db_session, fake_session_maker):
    """Une fois l'onboarding terminé, aucune relance J+1 (filtre structurel)."""
    user_id, _ = await _seed_abandoner(
        db_session, created_at=_ACTIVE_NOW - timedelta(hours=25)
    )
    # L'utilisateur revient et termine l'onboarding.
    profile = await db_session.scalar(
        select(UserProfile).where(UserProfile.user_id == user_id)
    )
    profile.onboarding_completed = True
    await db_session.commit()

    sender = Mock(return_value="message-id")
    with patch(
        "app.services.onboarding_reengagement_dispatcher.safe_async_session",
        fake_session_maker,
    ):
        metrics = await dispatch_onboarding_reengagement_pushes(
            now=_ACTIVE_NOW, sender=_sync(sender)
        )

    assert metrics["sent"] == 0
    assert sender.call_count == 0


@pytest.mark.asyncio
async def test_d1_after_24h_sends_both_relances(db_session, fake_session_maker):
    user_id, device_id = await _seed_abandoner(
        db_session, created_at=_ACTIVE_NOW - timedelta(hours=25)
    )
    sender = Mock(return_value="message-id")

    with patch(
        "app.services.onboarding_reengagement_dispatcher.safe_async_session",
        fake_session_maker,
    ):
        metrics = await dispatch_onboarding_reengagement_pushes(
            now=_ACTIVE_NOW, sender=_sync(sender)
        )

    # created_at > 24h → D0 (jamais envoyé) ET D1 partent dans le même run.
    assert metrics["sent"] == 2
    kinds = {call.args[3]["kind"] for call in sender.call_args_list}
    assert kinds == {KIND_D0, KIND_D1}
    deliveries = (
        (
            await db_session.execute(
                select(PushDelivery).where(PushDelivery.device_id == device_id)
            )
        )
        .scalars()
        .all()
    )
    assert {d.kind for d in deliveries} == {KIND_D0, KIND_D1}
    assert all(d.status == "sent" for d in deliveries)
    events = (
        (
            await db_session.execute(
                select(AnalyticsEvent).where(
                    AnalyticsEvent.user_id == user_id,
                    AnalyticsEvent.event_type == "push_sent",
                )
            )
        )
        .scalars()
        .all()
    )
    assert {e.event_data["kind"] for e in events} == {KIND_D0, KIND_D1}


@pytest.mark.asyncio
async def test_quiet_hours_defer(db_session, fake_session_maker):
    # 03:00 Paris = 01:00 UTC ; device créé 90 min avant → D0 dû mais heure calme.
    quiet_now = datetime(2026, 6, 15, 1, 0, tzinfo=UTC)
    _, device_id = await _seed_abandoner(
        db_session, created_at=quiet_now - timedelta(minutes=90)
    )
    sender = Mock(return_value="message-id")

    with patch(
        "app.services.onboarding_reengagement_dispatcher.safe_async_session",
        fake_session_maker,
    ):
        metrics = await dispatch_onboarding_reengagement_pushes(
            now=quiet_now, sender=_sync(sender)
        )

    assert metrics["sent"] == 0
    assert metrics["deferred"] == 1
    assert sender.call_count == 0
    delivery = await db_session.scalar(
        select(PushDelivery).where(
            PushDelivery.device_id == device_id, PushDelivery.kind == KIND_D0
        )
    )
    assert delivery is not None
    assert delivery.status == "pending"
    assert delivery.error_code == "quiet_hours"
    # Reporté au prochain 08:00 Paris (06:00 UTC le même jour).
    assert delivery.next_attempt_at == datetime(2026, 6, 15, 6, 0, tzinfo=UTC)


@pytest.mark.asyncio
async def test_invalid_token_revokes_device(db_session, fake_session_maker):
    _, device_id = await _seed_abandoner(
        db_session, created_at=_ACTIVE_NOW - timedelta(minutes=90)
    )

    class UnregisteredError(Exception):
        pass

    def invalid_sender(*_args):
        raise UnregisteredError("token is no longer valid")

    with patch(
        "app.services.onboarding_reengagement_dispatcher.safe_async_session",
        fake_session_maker,
    ):
        metrics = await dispatch_onboarding_reengagement_pushes(
            now=_ACTIVE_NOW, sender=invalid_sender
        )

    assert metrics["invalid_tokens"] == 1
    device = await db_session.scalar(
        select(PushDevice).where(PushDevice.device_id == device_id)
    )
    assert device is not None
    assert device.revoked_at is not None


@pytest.mark.asyncio
async def test_stale_device_excluded(db_session, fake_session_maker):
    # Device créé il y a 4 jours → hors fenêtre (STALE_AFTER = 3 j).
    await _seed_abandoner(db_session, created_at=_ACTIVE_NOW - timedelta(days=4))
    sender = Mock(return_value="message-id")

    with patch(
        "app.services.onboarding_reengagement_dispatcher.safe_async_session",
        fake_session_maker,
    ):
        metrics = await dispatch_onboarding_reengagement_pushes(
            now=_ACTIVE_NOW, sender=_sync(sender)
        )

    assert metrics["sent"] == 0
    assert sender.call_count == 0
