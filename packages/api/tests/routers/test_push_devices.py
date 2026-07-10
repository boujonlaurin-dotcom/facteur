from uuid import uuid4

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select

from app.database import get_db
from app.dependencies import get_current_user_id
from app.main import app
from app.models.push_notification import PushDevice
from app.models.user import UserProfile
from app.models.user_notification_preferences import UserNotificationPreferences
from app.routers import push_devices


@pytest_asyncio.fixture
async def push_auth_user(db_session, monkeypatch):
    monkeypatch.setattr(
        push_devices.settings,
        "firebase_service_account_json",
        '{"test": true}',
    )
    user_id = uuid4()
    db_session.add(
        UserProfile(
            user_id=user_id,
            display_name="Push Test User",
            onboarding_completed=True,
        )
    )
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
async def test_upsert_refresh_and_revoke_device(push_auth_user, db_session):
    device_id = uuid4()
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        first = await client.put(
            "/api/devices",
            json={
                "device_id": str(device_id),
                "fcm_token": "first-token-long-enough-for-validation",
                "platform": "ios",
                "timezone": "Europe/Paris",
                "app_version": "1.0.0+1",
            },
        )
        refreshed = await client.put(
            "/api/devices",
            json={
                "device_id": str(device_id),
                "fcm_token": "refreshed-token-long-enough-for-validation",
                "platform": "ios",
                "timezone": "America/Montreal",
                "app_version": "1.0.0+2",
            },
        )
        revoked = await client.delete(f"/api/devices/{device_id}")

    assert first.status_code == 200
    assert refreshed.status_code == 200
    assert revoked.status_code == 204
    device = await db_session.scalar(
        select(PushDevice).where(PushDevice.device_id == device_id)
    )
    assert device is not None
    assert device.user_id == push_auth_user
    assert device.fcm_token.startswith("refreshed-token")
    assert device.timezone == "America/Montreal"
    assert device.revoked_at is not None
    preferences = await db_session.scalar(
        select(UserNotificationPreferences).where(
            UserNotificationPreferences.user_id == push_auth_user
        )
    )
    assert preferences is not None
    assert preferences.timezone == "America/Montreal"


@pytest.mark.asyncio
async def test_multiple_devices_are_kept_for_same_user(push_auth_user, db_session):
    device_ids = [uuid4(), uuid4()]
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        for index, device_id in enumerate(device_ids):
            response = await client.put(
                "/api/devices",
                json={
                    "device_id": str(device_id),
                    "fcm_token": f"device-token-{index}-long-enough-to-be-valid",
                    "platform": "android",
                    "timezone": "Europe/Paris",
                },
            )
            assert response.status_code == 200

    devices = (
        await db_session.execute(
            select(PushDevice).where(PushDevice.user_id == push_auth_user)
        )
    ).scalars()
    assert {device.device_id for device in devices} == set(device_ids)
