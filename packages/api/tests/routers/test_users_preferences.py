"""Tests for PUT /api/users/preferences and the upsert_preference allowlist.

Defensive hardening post-PR #604 (Mode Serein auto-activation): verrouille
`upsert_preference` derrière une whitelist documentée pour bloquer toute
écriture future de clé inattendue dans `user_preferences`.
"""

from uuid import uuid4

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select

from app.database import get_db
from app.dependencies import get_current_user_id
from app.main import app
from app.models.user import UserPreference, UserProfile
from app.services.user_service import UserService


@pytest_asyncio.fixture
async def auth_user(db_session):
    """Create a UserProfile and override the auth + db dependencies."""
    user_id = uuid4()
    profile = UserProfile(
        user_id=user_id,
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
async def test_upsert_preference_allows_known_key(db_session):
    """Une clé de l'allowlist est persistée normalement."""
    user_id = uuid4()
    profile = UserProfile(user_id=user_id, onboarding_completed=True)
    db_session.add(profile)
    await db_session.commit()

    service = UserService(db_session)
    await service.upsert_preference(str(user_id), "serein_enabled", "true")

    row = (
        await db_session.execute(
            select(UserPreference).where(
                UserPreference.user_id == user_id,
                UserPreference.preference_key == "serein_enabled",
            )
        )
    ).scalar_one()
    assert row.preference_value == "true"


@pytest.mark.asyncio
async def test_upsert_preference_rejects_unknown_key(db_session):
    """Une clé hors allowlist lève ValueError sans écrire en base."""
    user_id = uuid4()
    profile = UserProfile(user_id=user_id, onboarding_completed=True)
    db_session.add(profile)
    await db_session.commit()

    service = UserService(db_session)
    with pytest.raises(ValueError, match="not allowed"):
        await service.upsert_preference(str(user_id), "wat", "x")

    rows = (
        (
            await db_session.execute(
                select(UserPreference).where(UserPreference.user_id == user_id)
            )
        )
        .scalars()
        .all()
    )
    assert rows == []


@pytest.mark.asyncio
async def test_put_preferences_accepts_known_key_http(auth_user):
    """PUT /users/preferences avec une clé valide → 200."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        resp = await ac.put(
            "/api/users/preferences",
            json={"key": "serein_enabled", "value": "true"},
        )
    assert resp.status_code == 200
    body = resp.json()
    assert body == {"success": True, "key": "serein_enabled", "value": "true"}


@pytest.mark.asyncio
async def test_put_preferences_rejects_unknown_key_http(auth_user):
    """PUT /users/preferences avec une clé inconnue → 422 (Pydantic)."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        resp = await ac.put(
            "/api/users/preferences",
            json={"key": "wat", "value": "x"},
        )
    assert resp.status_code == 422
