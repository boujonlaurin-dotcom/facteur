"""Dispatch des alertes « source rare » (story 30.2)."""

from datetime import UTC, datetime, timedelta
from unittest.mock import Mock, patch
from uuid import uuid4

import pytest
from sqlalchemy import select

from app.models.content import Content
from app.models.enums import ContentType, InterestState, SourceType
from app.models.push_notification import PushDelivery, PushDevice
from app.models.source import Source, UserSource
from app.models.user import UserProfile
from app.models.user_notification_preferences import UserNotificationPreferences
from app.services.push_alert_dispatcher import dispatch_source_alerts
from app.services.source_alert_producer import source_alert_kind

# 08:35 Paris = dans le créneau « morning » (07:30–12:00).
NOW = datetime(2026, 7, 26, 6, 35, tzinfo=UTC)


async def _seed_push_user(db_session):
    user_id = uuid4()
    device_id = uuid4()
    db_session.add(
        UserProfile(
            user_id=user_id,
            display_name="Alert Dispatcher User",
            onboarding_completed=True,
        )
    )
    await db_session.flush()
    db_session.add_all(
        [
            UserNotificationPreferences(
                user_id=user_id,
                push_enabled=True,
                time_slot="morning",
                timezone="Europe/Paris",
            ),
            PushDevice(
                device_id=device_id,
                user_id=user_id,
                fcm_token="alert-token",
                platform="android",
                timezone="Europe/Paris",
            ),
        ]
    )
    await db_session.flush()
    return user_id, device_id


async def _seed_rare_source_with_fresh_article(
    db_session, user_id, *, name="Le Mensuel", title="Une parution rare"
):
    """Source à ~2 articles / 30 j (rare) avec une parution il y a 2 h."""
    source = Source(
        id=uuid4(),
        name=name,
        url=f"https://{uuid4()}.example.com",
        feed_url=f"https://{uuid4()}.example.com/feed.xml",
        type=SourceType.ARTICLE,
        theme="society",
        is_active=True,
        is_curated=True,
    )
    db_session.add(source)
    await db_session.flush()
    db_session.add_all(
        [
            Content(
                id=uuid4(),
                source_id=source.id,
                title=title,
                url=f"https://example.com/{uuid4()}",
                guid=str(uuid4()),
                published_at=NOW - timedelta(hours=2),
                content_type=ContentType.ARTICLE,
                theme="society",
            ),
            Content(
                id=uuid4(),
                source_id=source.id,
                title="Archive",
                url=f"https://example.com/{uuid4()}",
                guid=str(uuid4()),
                published_at=NOW - timedelta(days=29),
                content_type=ContentType.ARTICLE,
                theme="society",
            ),
        ]
    )
    db_session.add(
        UserSource(
            user_id=user_id,
            source_id=source.id,
            state=InterestState.FOLLOWED,
            notify=True,
        )
    )
    await db_session.flush()
    return source


@pytest.mark.asyncio
async def test_sends_alert_payload_and_is_idempotent(db_session, fake_session_maker):
    user_id, device_id = await _seed_push_user(db_session)
    source = await _seed_rare_source_with_fresh_article(db_session, user_id)
    await db_session.commit()

    sender = Mock(return_value="message-id")

    def sync_sender(*args):
        return sender(*args)

    with patch(
        "app.services.push_alert_dispatcher.safe_async_session",
        fake_session_maker,
    ):
        first = await dispatch_source_alerts(now=NOW, sender=sync_sender)
        second = await dispatch_source_alerts(now=NOW, sender=sync_sender)

    assert first["sent"] == 1
    assert second["sent"] == 0
    assert sender.call_count == 1

    _token, title, body, data = sender.call_args[0]
    assert title == "📯 Alerte : Le Mensuel vient de publier"
    assert body == "Une parution rare"
    assert data["kind"] == "source_alert"
    assert data["source_id"] == str(source.id)
    assert data["channel"] == "alerts"
    assert data["route"].startswith("/article/")
    assert "Ça n'arrive qu'une fois" in data["big_text"]

    delivery = await db_session.scalar(
        select(PushDelivery).where(PushDelivery.device_id == device_id)
    )
    assert delivery.status == "sent"
    assert delivery.kind == source_alert_kind(source.id)


@pytest.mark.asyncio
async def test_two_sources_same_day_produce_two_deliveries(
    db_session, fake_session_maker
):
    """Le kind composite est ce qui évite la collision d'unicité."""
    user_id, device_id = await _seed_push_user(db_session)
    first_source = await _seed_rare_source_with_fresh_article(
        db_session, user_id, name="Le Mensuel"
    )
    second_source = await _seed_rare_source_with_fresh_article(
        db_session, user_id, name="La Revue"
    )
    await db_session.commit()

    with patch(
        "app.services.push_alert_dispatcher.safe_async_session",
        fake_session_maker,
    ):
        # 1er passage : la 1ʳᵉ alerte part, la 2ᵉ est gouvernée (budget 2/24h
        # atteint dès que la 1ʳᵉ est comptée) — ce qui compte ici est que les
        # DEUX lignes existent, avec des kinds distincts.
        await dispatch_source_alerts(now=NOW, sender=lambda *_: "ok")

    deliveries = (
        (
            await db_session.execute(
                select(PushDelivery).where(PushDelivery.device_id == device_id)
            )
        )
        .scalars()
        .all()
    )
    kinds = {d.kind for d in deliveries}
    assert kinds == {
        source_alert_kind(first_source.id),
        source_alert_kind(second_source.id),
    }


@pytest.mark.asyncio
async def test_governor_refusal_is_final(db_session, fake_session_maker):
    """Refus gouverneur → `skipped` définitif, jamais rejoué le lendemain."""
    user_id, device_id = await _seed_push_user(db_session)
    source = await _seed_rare_source_with_fresh_article(db_session, user_id)
    # Budget journalier déjà épuisé par deux autres pushes.
    for kind, hours in (("daily_digest", 1), ("other_alert", 2)):
        db_session.add(
            PushDelivery(
                device_id=device_id,
                target_date=(NOW - timedelta(hours=hours)).date(),
                kind=kind,
                status="sent",
                sent_at=NOW - timedelta(hours=hours),
            )
        )
    await db_session.commit()

    sender = Mock(return_value="message-id")
    with patch(
        "app.services.push_alert_dispatcher.safe_async_session",
        fake_session_maker,
    ):
        metrics = await dispatch_source_alerts(now=NOW, sender=lambda *a: sender(*a))

    assert metrics["sent"] == 0
    assert metrics["governed"] == 1
    assert sender.call_count == 0

    delivery = await db_session.scalar(
        select(PushDelivery).where(
            PushDelivery.kind == source_alert_kind(source.id),
        )
    )
    assert delivery.status == "skipped"
    assert delivery.error_code == "daily_budget_exceeded"


@pytest.mark.asyncio
async def test_ritual_cooldown_does_not_block_alerts(db_session, fake_session_maker):
    """La tournée envoyée il y a 1 h ne doit pas étouffer la cloche."""
    user_id, device_id = await _seed_push_user(db_session)
    await _seed_rare_source_with_fresh_article(db_session, user_id)
    db_session.add(
        PushDelivery(
            device_id=device_id,
            target_date=NOW.date(),
            kind="daily_digest",
            status="sent",
            sent_at=NOW - timedelta(hours=1),
        )
    )
    await db_session.commit()

    with patch(
        "app.services.push_alert_dispatcher.safe_async_session",
        fake_session_maker,
    ):
        metrics = await dispatch_source_alerts(now=NOW, sender=lambda *_: "ok")

    assert metrics["sent"] == 1
    assert metrics["governed"] == 0


@pytest.mark.asyncio
async def test_outside_user_time_slot_nothing_is_sent(db_session, fake_session_maker):
    user_id, _ = await _seed_push_user(db_session)
    await _seed_rare_source_with_fresh_article(db_session, user_id)
    await db_session.commit()

    # 03:00 Paris : hors du créneau « morning ».
    early = datetime(2026, 7, 26, 1, 0, tzinfo=UTC)
    with patch(
        "app.services.push_alert_dispatcher.safe_async_session",
        fake_session_maker,
    ):
        metrics = await dispatch_source_alerts(now=early, sender=lambda *_: "ok")

    assert metrics["sent"] == 0
    assert (await db_session.execute(select(PushDelivery))).scalars().first() is None
