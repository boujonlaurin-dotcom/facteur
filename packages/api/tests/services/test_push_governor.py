from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest

from app.models.push_notification import PushDelivery, PushDevice
from app.models.user import UserProfile
from app.services.push_governor import check_push_budget

NOW = datetime(2026, 7, 18, 12, 0, tzinfo=UTC)


async def _seed_user(db_session, *, devices=1):
    user_id = uuid4()
    db_session.add(
        UserProfile(
            user_id=user_id,
            display_name="Governor User",
            onboarding_completed=True,
        )
    )
    await db_session.flush()
    device_ids = []
    for i in range(devices):
        device_id = uuid4()
        device_ids.append(device_id)
        db_session.add(
            PushDevice(
                device_id=device_id,
                user_id=user_id,
                fcm_token=f"governor-token-{i}",
                platform="android",
                timezone="Europe/Paris",
            )
        )
    await db_session.flush()
    return user_id, device_ids


def _delivery(device_id, *, kind, sent_at, status="sent"):
    return PushDelivery(
        device_id=device_id,
        target_date=sent_at.date(),
        kind=kind,
        status=status,
        sent_at=sent_at if status == "sent" else None,
    )


@pytest.mark.asyncio
async def test_allows_first_push_of_the_day(db_session):
    user_id, _ = await _seed_user(db_session)
    await db_session.commit()

    decision = await check_push_budget(
        db_session, user_id=user_id, kind="daily_digest", now=NOW
    )
    assert decision.allowed


@pytest.mark.asyncio
async def test_daily_budget_blocks_third_push_in_24h(db_session):
    user_id, (device_id,) = await _seed_user(db_session)
    db_session.add_all(
        [
            _delivery(device_id, kind="daily_digest", sent_at=NOW - timedelta(hours=5)),
            _delivery(
                device_id, kind="source_alert", sent_at=NOW - timedelta(hours=10)
            ),
        ]
    )
    await db_session.commit()

    decision = await check_push_budget(
        db_session, user_id=user_id, kind="topic_alert", now=NOW
    )
    assert not decision.allowed
    assert decision.reason == "daily_budget_exceeded"


@pytest.mark.asyncio
async def test_daily_window_is_sliding_not_calendar(db_session):
    user_id, (device_id,) = await _seed_user(db_session)
    # 2 pushes il y a 25h : hors fenêtre 24h, mais dans la fenêtre 7j.
    db_session.add_all(
        [
            _delivery(
                device_id, kind="daily_digest", sent_at=NOW - timedelta(hours=25)
            ),
            _delivery(
                device_id, kind="source_alert", sent_at=NOW - timedelta(hours=26)
            ),
        ]
    )
    await db_session.commit()

    decision = await check_push_budget(
        db_session, user_id=user_id, kind="source_alert", now=NOW
    )
    assert decision.allowed


@pytest.mark.asyncio
async def test_weekly_budget_blocks_seventh_push(db_session):
    user_id, (device_id,) = await _seed_user(db_session)
    db_session.add_all(
        [
            _delivery(
                device_id, kind="daily_digest", sent_at=NOW - timedelta(days=d, hours=6)
            )
            for d in range(1, 7)
        ]
    )
    await db_session.commit()

    decision = await check_push_budget(
        db_session, user_id=user_id, kind="source_alert", now=NOW
    )
    assert not decision.allowed
    assert decision.reason == "weekly_budget_exceeded"


@pytest.mark.asyncio
async def test_multi_devices_same_logical_push_count_once(db_session):
    user_id, device_ids = await _seed_user(db_session, devices=3)
    sent_at = NOW - timedelta(hours=6)
    for device_id in device_ids:
        db_session.add(_delivery(device_id, kind="daily_digest", sent_at=sent_at))
    await db_session.commit()

    # 3 devices = 1 push logique → le budget quotidien (2) n'est pas atteint.
    decision = await check_push_budget(
        db_session, user_id=user_id, kind="source_alert", now=NOW
    )
    assert decision.allowed


@pytest.mark.asyncio
async def test_same_logical_push_does_not_block_its_other_devices(db_session):
    user_id, device_ids = await _seed_user(db_session, devices=2)
    # Device 1 déjà servi aujourd'hui + un autre kind dans la fenêtre 24h :
    # le device 2 du MÊME push logique (target_date, kind) doit passer.
    db_session.add_all(
        [
            _delivery(
                device_ids[0], kind="daily_digest", sent_at=NOW - timedelta(minutes=10)
            ),
            _delivery(
                device_ids[0], kind="source_alert", sent_at=NOW - timedelta(hours=10)
            ),
        ]
    )
    await db_session.commit()

    decision = await check_push_budget(
        db_session,
        user_id=user_id,
        kind="daily_digest",
        now=NOW,
        target_date=NOW.date(),
    )
    assert decision.allowed


@pytest.mark.asyncio
async def test_non_ritual_blocked_within_4h_after_ritual(db_session):
    user_id, (device_id,) = await _seed_user(db_session)
    db_session.add(
        _delivery(device_id, kind="daily_digest", sent_at=NOW - timedelta(hours=3))
    )
    await db_session.commit()

    decision = await check_push_budget(
        db_session, user_id=user_id, kind="source_alert", now=NOW
    )
    assert not decision.allowed
    assert decision.reason == "ritual_cooldown"


@pytest.mark.asyncio
async def test_non_ritual_blocked_when_ritual_upcoming_within_4h(db_session):
    user_id, _ = await _seed_user(db_session)
    await db_session.commit()

    decision = await check_push_budget(
        db_session,
        user_id=user_id,
        kind="source_alert",
        now=NOW,
        next_ritual_at=NOW + timedelta(hours=2),
    )
    assert not decision.allowed
    assert decision.reason == "ritual_upcoming"


@pytest.mark.asyncio
async def test_non_ritual_allowed_when_ritual_far_enough(db_session):
    user_id, (device_id,) = await _seed_user(db_session)
    db_session.add(
        _delivery(device_id, kind="daily_digest", sent_at=NOW - timedelta(hours=5))
    )
    await db_session.commit()

    decision = await check_push_budget(
        db_session,
        user_id=user_id,
        kind="source_alert",
        now=NOW,
        next_ritual_at=NOW + timedelta(hours=6),
    )
    assert decision.allowed


@pytest.mark.asyncio
async def test_ritual_kind_exempt_from_cooldown_but_not_from_budgets(db_session):
    user_id, (device_id,) = await _seed_user(db_session)
    # Un rituel envoyé il y a 1h ne bloque pas un autre envoi rituel (autre
    # target_date, ex. rattrapage) par le cooldown...
    db_session.add(
        _delivery(device_id, kind="daily_digest", sent_at=NOW - timedelta(hours=1))
    )
    await db_session.commit()

    decision = await check_push_budget(
        db_session, user_id=user_id, kind="daily_digest", now=NOW
    )
    assert decision.allowed

    # ... mais les budgets s'appliquent : 2 pushes distincts en 24h → refus.
    db_session.add(
        _delivery(device_id, kind="source_alert", sent_at=NOW - timedelta(hours=2))
    )
    await db_session.commit()
    decision = await check_push_budget(
        db_session, user_id=user_id, kind="daily_digest", now=NOW
    )
    assert not decision.allowed
    assert decision.reason == "daily_budget_exceeded"


@pytest.mark.asyncio
async def test_ritual_companion_passes_despite_recent_ritual(db_session):
    """Une alerte accompagne la tournée au lieu de lui disputer son créneau."""
    user_id, (device_id,) = await _seed_user(db_session)
    db_session.add(
        _delivery(device_id, kind="daily_digest", sent_at=NOW - timedelta(hours=1))
    )
    await db_session.commit()

    refused = await check_push_budget(
        db_session, user_id=user_id, kind="source_alert:abc", now=NOW
    )
    assert refused.reason == "ritual_cooldown"

    decision = await check_push_budget(
        db_session,
        user_id=user_id,
        kind="source_alert:abc",
        now=NOW,
        ritual_companion=True,
    )
    assert decision.allowed


@pytest.mark.asyncio
async def test_ritual_companion_ignores_upcoming_ritual(db_session):
    user_id, _ = await _seed_user(db_session)
    await db_session.commit()

    decision = await check_push_budget(
        db_session,
        user_id=user_id,
        kind="source_alert:abc",
        now=NOW,
        next_ritual_at=NOW + timedelta(hours=2),
        ritual_companion=True,
    )
    assert decision.allowed


@pytest.mark.asyncio
async def test_ritual_companion_still_bound_by_daily_budget(db_session):
    """L'exemption ne porte que sur le cooldown : les budgets tiennent."""
    user_id, (device_id,) = await _seed_user(db_session)
    db_session.add_all(
        [
            _delivery(device_id, kind="daily_digest", sent_at=NOW - timedelta(hours=1)),
            _delivery(
                device_id, kind="source_alert:abc", sent_at=NOW - timedelta(hours=2)
            ),
        ]
    )
    await db_session.commit()

    decision = await check_push_budget(
        db_session,
        user_id=user_id,
        kind="source_alert:def",
        now=NOW,
        ritual_companion=True,
    )
    assert not decision.allowed
    assert decision.reason == "daily_budget_exceeded"


@pytest.mark.asyncio
async def test_ignores_non_sent_and_other_users(db_session):
    user_id, (device_id,) = await _seed_user(db_session)
    other_user, (other_device,) = await _seed_user(db_session)
    db_session.add_all(
        [
            _delivery(
                device_id,
                kind="daily_digest",
                sent_at=NOW - timedelta(hours=1),
                status="skipped",
            ),
            _delivery(
                other_device, kind="daily_digest", sent_at=NOW - timedelta(hours=1)
            ),
            _delivery(
                other_device, kind="source_alert", sent_at=NOW - timedelta(hours=2)
            ),
        ]
    )
    await db_session.commit()

    decision = await check_push_budget(
        db_session, user_id=user_id, kind="source_alert", now=NOW
    )
    assert decision.allowed
