from datetime import UTC, date, datetime
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock, patch
from uuid import uuid4

import pytest
from sqlalchemy import select

from app.models.push_notification import PushDelivery, PushDevice
from app.models.user import UserProfile
from app.models.user_notification_preferences import UserNotificationPreferences
from app.services.push_dispatcher import (
    _build_exact_essentiel,
    _is_due,
    dispatch_daily_essentiel_pushes,
)


def _unused_sender(_token, _title, _body, _data):
    return "unused"


async def _seed_push_user(db_session, *, timezone="Europe/Paris", slot="morning"):
    user_id = uuid4()
    device_id = uuid4()
    db_session.add(
        UserProfile(
            user_id=user_id,
            display_name="Dispatcher User",
            onboarding_completed=True,
        )
    )
    await db_session.flush()
    db_session.add_all(
        [
            UserNotificationPreferences(
                user_id=user_id,
                push_enabled=True,
                time_slot=slot,
                timezone=timezone,
            ),
            PushDevice(
                device_id=device_id,
                user_id=user_id,
                fcm_token="dispatcher-token",
                platform="android",
                timezone=timezone,
            ),
        ]
    )
    await db_session.commit()
    return user_id, device_id


@pytest.mark.asyncio
async def test_dispatch_is_idempotent_per_device_and_local_date(
    db_session, fake_session_maker
):
    _, device_id = await _seed_push_user(db_session)
    sender = Mock(return_value="message-id")

    def sync_sender(*args):
        return sender(*args)

    essentiel = SimpleNamespace(articles=[SimpleNamespace(title="Sujet exact du jour")])
    now = datetime(2026, 6, 15, 6, 35, tzinfo=UTC)  # 08:35 Paris
    with (
        patch(
            "app.services.push_dispatcher.safe_async_session",
            fake_session_maker,
        ),
        patch(
            "app.services.push_dispatcher._build_exact_essentiel",
            new=AsyncMock(return_value=essentiel),
        ),
    ):
        first = await dispatch_daily_essentiel_pushes(now=now, sender=sync_sender)
        second = await dispatch_daily_essentiel_pushes(now=now, sender=sync_sender)

    assert first["sent"] == 1
    assert second["sent"] == 0
    assert sender.call_count == 1
    delivery = await db_session.scalar(
        select(PushDelivery).where(PushDelivery.device_id == device_id)
    )
    assert delivery is not None
    assert delivery.status == "sent"
    assert delivery.target_date == date(2026, 6, 15)


@pytest.mark.asyncio
async def test_missing_morning_digest_retries_then_skips_at_noon(
    db_session, fake_session_maker
):
    _, device_id = await _seed_push_user(db_session)
    with (
        patch(
            "app.services.push_dispatcher.safe_async_session",
            fake_session_maker,
        ),
        patch(
            "app.services.push_dispatcher._build_exact_essentiel",
            new=AsyncMock(return_value=None),
        ),
    ):
        retry = await dispatch_daily_essentiel_pushes(
            now=datetime(2026, 6, 15, 6, 0, tzinfo=UTC),
            sender=_unused_sender,
        )
        delivery = await db_session.scalar(
            select(PushDelivery).where(PushDelivery.device_id == device_id)
        )
        assert delivery is not None
        delivery.next_attempt_at = datetime(2026, 6, 15, 10, 0, tzinfo=UTC)
        await db_session.flush()
        skipped = await dispatch_daily_essentiel_pushes(
            now=datetime(2026, 6, 15, 10, 0, tzinfo=UTC),
            sender=_unused_sender,
        )

    assert retry["retried"] == 1
    assert skipped["skipped"] == 1
    assert delivery.status == "skipped"
    assert delivery.error_code == "digest_missing_at_cutoff"


@pytest.mark.asyncio
async def test_invalid_fcm_token_revokes_device(db_session, fake_session_maker):
    _, device_id = await _seed_push_user(db_session)

    class UnregisteredError(Exception):
        pass

    def invalid_sender(*args):
        raise UnregisteredError("token is no longer valid")

    with (
        patch(
            "app.services.push_dispatcher.safe_async_session",
            fake_session_maker,
        ),
        patch(
            "app.services.push_dispatcher._build_exact_essentiel",
            new=AsyncMock(
                return_value=SimpleNamespace(
                    articles=[SimpleNamespace(title="Sujet du jour")]
                )
            ),
        ),
    ):
        metrics = await dispatch_daily_essentiel_pushes(
            now=datetime(2026, 6, 15, 6, 35, tzinfo=UTC),
            sender=invalid_sender,
        )

    device = await db_session.scalar(
        select(PushDevice).where(PushDevice.device_id == device_id)
    )
    assert metrics["invalid_tokens"] == 1
    assert device is not None
    assert device.revoked_at is not None


@pytest.mark.asyncio
async def test_exact_digest_builder_rejects_yesterday_response():
    target = date(2026, 6, 15)
    digest = SimpleNamespace(format_version="topics_v1")
    session = AsyncMock()
    session.scalar.return_value = digest
    stale_response = SimpleNamespace(
        target_date=date(2026, 6, 14),
        is_stale_fallback=True,
    )

    with patch(
        "app.services.push_dispatcher.DigestService._build_digest_response",
        new=AsyncMock(return_value=stale_response),
    ):
        result = await _build_exact_essentiel(session, uuid4(), target)

    assert result is None


def test_due_time_uses_each_users_local_timezone():
    montreal_morning = datetime(2026, 6, 15, 7, 30)
    paris_before_evening = datetime(2026, 6, 15, 18, 59)

    assert _is_due(montreal_morning, "morning") is True
    assert _is_due(paris_before_evening, "evening") is False


def test_send_fcm_is_data_only_with_teasers_preserved():
    """Android doit recevoir un message data-only (pas de bloc `notification`
    top-level) pour que le background handler rende les bullets ; les teasers
    et le title/body doivent rester lisibles dans `data`. iOS garde un alert
    APNS visible.
    """
    import sys
    from types import SimpleNamespace

    captured: dict[str, object] = {}

    def _message(**kwargs):
        captured.update(kwargs)
        return SimpleNamespace(**kwargs)

    fake_messaging = SimpleNamespace(
        Message=_message,
        Notification=lambda **k: SimpleNamespace(**k),
        AndroidConfig=lambda **k: SimpleNamespace(kind="android", **k),
        AndroidNotification=lambda **k: SimpleNamespace(**k),
        APNSConfig=lambda **k: SimpleNamespace(kind="apns", **k),
        APNSPayload=lambda **k: SimpleNamespace(**k),
        Aps=lambda **k: SimpleNamespace(**k),
        ApsAlert=lambda **k: SimpleNamespace(kind="aps_alert", **k),
        send=lambda *_args, **_kwargs: "message-id",
    )
    fake_firebase_admin = SimpleNamespace(messaging=fake_messaging)

    from app.services import push_dispatcher

    data = {
        "route": "/digest",
        "kind": "daily_digest",
        "teasers": '["Trump", "Climat"]',
    }
    with (
        patch.object(push_dispatcher, "_firebase_app", return_value=object()),
        patch.dict(sys.modules, {"firebase_admin": fake_firebase_admin}),
    ):
        result = push_dispatcher._send_fcm("tok", "Facteur", "Trump", data)

    assert result == "message-id"
    # Pas de notification top-level (data-only) → Android invoque le bg handler.
    assert captured.get("notification") is None
    # Android config sans rendu notification.
    assert getattr(captured["android"], "kind", None) == "android"
    assert getattr(captured["android"], "notification", None) is None
    # teasers + title/body conservés dans data pour le rendu client.
    assert captured["data"]["teasers"] == '["Trump", "Climat"]'
    assert captured["data"]["title"] == "Facteur"
    assert captured["data"]["body"] == "Trump"
    # iOS conserve un alert visible.
    assert getattr(captured["apns"], "kind", None) == "apns"
