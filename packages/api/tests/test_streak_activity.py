from datetime import date, datetime, timedelta
from uuid import uuid4

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select

from app.database import get_db
from app.dependencies import get_current_user_id
from app.main import app
from app.models.analytics import AnalyticsEvent
from app.models.user import UserProfile, UserStreak


def _override_db(session):
    async def _fake_db():
        yield session

    return _fake_db


def _override_user(user_id: str):
    async def _fake_user():
        return user_id

    return _fake_user


async def _create_profile(db_session, user_id, *, gamification_enabled: bool):
    profile = UserProfile(
        user_id=user_id,
        gamification_enabled=gamification_enabled,
        onboarding_completed=True,
        weekly_goal=5,
    )
    db_session.add(profile)
    await db_session.commit()
    return profile


@pytest.mark.asyncio
async def test_session_start_same_local_date_is_idempotent(db_session):
    user_id = uuid4()
    await _create_profile(db_session, user_id, gamification_enabled=True)

    app.dependency_overrides[get_current_user_id] = _override_user(str(user_id))
    app.dependency_overrides[get_db] = _override_db(db_session)

    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            for _ in range(2):
                response = await ac.post(
                    "/api/analytics/events",
                    json={
                        "event_type": "session_start",
                        "event_data": {"local_date": "2026-05-26"},
                    },
                )
                assert response.status_code == 201
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)
        app.dependency_overrides.pop(get_db, None)

    streak = await db_session.scalar(
        select(UserStreak).where(UserStreak.user_id == user_id)
    )
    assert streak is not None
    assert streak.current_streak == 1
    assert streak.longest_streak == 1
    assert streak.last_activity_date == date(2026, 5, 26)

    events = (
        await db_session.execute(
            select(AnalyticsEvent).where(AnalyticsEvent.user_id == user_id)
        )
    ).scalars().all()
    assert len(events) == 2


@pytest.mark.asyncio
async def test_session_start_consecutive_days_then_gap_resets_streak(db_session):
    user_id = uuid4()
    await _create_profile(db_session, user_id, gamification_enabled=True)

    app.dependency_overrides[get_current_user_id] = _override_user(str(user_id))
    app.dependency_overrides[get_db] = _override_db(db_session)

    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            for local_date in ("2026-05-24", "2026-05-25", "2026-05-27"):
                response = await ac.post(
                    "/api/analytics/events",
                    json={
                        "event_type": "session_start",
                        "event_data": {"local_date": local_date},
                    },
                )
                assert response.status_code == 201
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)
        app.dependency_overrides.pop(get_db, None)

    streak = await db_session.scalar(
        select(UserStreak).where(UserStreak.user_id == user_id)
    )
    assert streak is not None
    assert streak.current_streak == 1
    assert streak.longest_streak == 2
    assert streak.last_activity_date == date(2026, 5, 27)


@pytest.mark.asyncio
async def test_session_start_logs_analytics_but_skips_streak_when_gamification_disabled(
    db_session,
):
    user_id = uuid4()
    await _create_profile(db_session, user_id, gamification_enabled=False)

    app.dependency_overrides[get_current_user_id] = _override_user(str(user_id))
    app.dependency_overrides[get_db] = _override_db(db_session)

    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            response = await ac.post(
                "/api/analytics/events",
                json={
                    "event_type": "session_start",
                    "event_data": {"local_date": "2026-05-26"},
                },
            )
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)
        app.dependency_overrides.pop(get_db, None)

    assert response.status_code == 201
    event = await db_session.scalar(
        select(AnalyticsEvent).where(AnalyticsEvent.user_id == user_id)
    )
    assert event is not None
    assert event.event_type == "session_start"

    streak = await db_session.scalar(
        select(UserStreak).where(UserStreak.user_id == user_id)
    )
    assert streak is None


@pytest.mark.asyncio
async def test_streak_activity_endpoint_returns_opened_days_and_articles_read(
    db_session,
):
    user_id = uuid4()
    today = date.today()
    day_1 = today - timedelta(days=3)
    day_2 = today - timedelta(days=2)
    day_3 = today - timedelta(days=1)
    await _create_profile(db_session, user_id, gamification_enabled=True)

    db_session.add_all(
        [
            UserStreak(
                user_id=user_id,
                current_streak=2,
                longest_streak=3,
                last_activity_date=today,
            ),
            AnalyticsEvent(
                user_id=user_id,
                event_type="session_start",
                event_data={"local_date": day_1.isoformat()},
                created_at=datetime.combine(day_1, datetime.min.time()).replace(hour=8),
            ),
            AnalyticsEvent(
                user_id=user_id,
                event_type="article_read",
                event_data={"local_date": day_2.isoformat()},
                created_at=datetime.combine(day_2, datetime.min.time()).replace(hour=7),
            ),
            AnalyticsEvent(
                user_id=user_id,
                event_type="session_start",
                event_data={"local_date": day_3.isoformat()},
                created_at=datetime.combine(day_3, datetime.min.time()).replace(hour=8),
            ),
            AnalyticsEvent(
                user_id=user_id,
                event_type="content_interaction",
                event_data={"action": "save", "local_date": day_2.isoformat()},
                created_at=datetime.combine(day_2, datetime.min.time()).replace(hour=7, minute=30),
            ),
            AnalyticsEvent(
                user_id=user_id,
                event_type="session_start",
                event_data={"local_date": today.isoformat()},
                created_at=datetime.combine(today, datetime.min.time()).replace(hour=8),
            ),
            AnalyticsEvent(
                user_id=user_id,
                event_type="content_interaction",
                event_data={"action": "read", "local_date": day_3.isoformat()},
                created_at=datetime.combine(day_3, datetime.min.time()).replace(hour=9),
            ),
            AnalyticsEvent(
                user_id=user_id,
                event_type="article_read",
                event_data={"local_date": today.isoformat()},
                created_at=datetime.combine(today, datetime.min.time()).replace(hour=9),
            ),
            AnalyticsEvent(
                user_id=user_id,
                event_type="content_interaction",
                event_data={"action": "save", "local_date": today.isoformat()},
                created_at=datetime.combine(today, datetime.min.time()).replace(hour=9, minute=5),
            ),
        ]
    )
    await db_session.commit()

    app.dependency_overrides[get_current_user_id] = _override_user(str(user_id))
    app.dependency_overrides[get_db] = _override_db(db_session)

    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            response = await ac.get("/api/streaks/activity?days=4")
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)
        app.dependency_overrides.pop(get_db, None)

    assert response.status_code == 200
    body = response.json()
    assert body["current_streak"] == 2
    assert body["longest_streak"] == 3
    assert body["last_activity_date"] == today.isoformat()
    assert body["days"] == [
        {"date": day_1.isoformat(), "opened": True, "articles_read": None},
        {"date": day_2.isoformat(), "opened": True, "articles_read": 1},
        {"date": day_3.isoformat(), "opened": True, "articles_read": 1},
        {"date": today.isoformat(), "opened": True, "articles_read": 1},
    ]
