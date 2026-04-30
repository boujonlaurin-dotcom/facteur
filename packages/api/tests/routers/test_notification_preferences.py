"""Tests pour le router /api/notification-preferences."""

from uuid import uuid4

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from app.database import get_db
from app.dependencies import get_current_user_id
from app.main import app
from app.models.user import UserProfile


@pytest_asyncio.fixture
async def auth_user(db_session):
    user_id = uuid4()
    profile = UserProfile(
        user_id=user_id,
        display_name="Notif Test User",
        onboarding_completed=True,
    )
    db_session.add(profile)
    await db_session.commit()

    async def _fake_user():
        return str(user_id)

    async def _fake_db():
        yield db_session

    app.dependency_overrides[get_current_user_id] = _fake_user
    app.dependency_overrides[get_db] = _fake_db
    try:
        yield user_id
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)
        app.dependency_overrides.pop(get_db, None)


@pytest.mark.asyncio
async def test_get_returns_defaults_and_auto_creates(auth_user):
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        resp = await ac.get("/api/notification-preferences/")

    assert resp.status_code == 200
    body = resp.json()
    assert body["push_enabled"] is False
    assert body["preset"] == "minimaliste"
    assert body["time_slot"] == "morning"
    assert body["timezone"] == "Europe/Paris"
    assert body["modal_seen"] is False
    assert body["refusal_count"] == 0
    assert body["renudge_shown_count"] == 0


@pytest.mark.asyncio
async def test_patch_updates_preset_and_time_slot(auth_user):
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        await ac.get("/api/notification-preferences/")
        resp = await ac.patch(
            "/api/notification-preferences/",
            json={
                "push_enabled": True,
                "preset": "curieux",
                "time_slot": "evening",
                "modal_seen": True,
            },
        )

    assert resp.status_code == 200
    body = resp.json()
    assert body["push_enabled"] is True
    assert body["preset"] == "curieux"
    assert body["time_slot"] == "evening"
    assert body["modal_seen"] is True


@pytest.mark.asyncio
async def test_patch_rejects_invalid_preset(auth_user):
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        resp = await ac.patch(
            "/api/notification-preferences/",
            json={"preset": "anarchic"},
        )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_patch_increments_refusal_count(auth_user):
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        await ac.get("/api/notification-preferences/")
        resp = await ac.patch(
            "/api/notification-preferences/",
            json={
                "refusal_count": 1,
                "last_refusal_at": "2026-04-28T12:00:00+00:00",
            },
        )

    assert resp.status_code == 200
    body = resp.json()
    assert body["refusal_count"] == 1
    assert body["last_refusal_at"].startswith("2026-04-28T12:00:00")
