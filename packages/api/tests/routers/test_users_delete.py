"""Tests for DELETE /api/users/me (App Store 5.1.1(v) compliance)."""

from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select

from app.database import get_db
from app.dependencies import get_current_user_id
from app.main import app
from app.models.user import UserInterest, UserPreference, UserProfile


@pytest_asyncio.fixture
async def auth_user(db_session):
    """Create a UserProfile and override the auth + db dependencies."""
    user_id = uuid4()
    profile = UserProfile(
        user_id=user_id,
        display_name="To Delete",
        age_range="25-34",
        gender="other",
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
async def test_delete_me_anonymizes_profile(auth_user, db_session):
    """Happy path: profile is anonymised, email_hash stored, 204 returned."""
    transport = ASGITransport(app=app)
    with (
        patch(
            "app.routers.users._fetch_auth_email",
            new=AsyncMock(return_value="alice@example.com"),
        ),
        patch(
            "app.routers.users._delete_supabase_auth_user",
            new=AsyncMock(return_value=None),
        ) as supa_mock,
    ):
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            resp = await ac.delete("/api/users/me")

    assert resp.status_code == 204
    assert resp.content == b""
    supa_mock.assert_awaited_once_with(str(auth_user))

    # Profil anonymisé en DB
    profile = (
        await db_session.execute(
            select(UserProfile).where(UserProfile.user_id == auth_user)
        )
    ).scalar_one()
    assert profile.deleted_at is not None
    assert profile.display_name is None
    assert profile.age_range is None
    assert profile.gender is None
    # SHA256 hex digest = 64 chars
    assert profile.email_hash is not None
    assert len(profile.email_hash) == 64
    # Hash déterministe vs email injecté
    import hashlib

    assert profile.email_hash == hashlib.sha256(b"alice@example.com").hexdigest()


@pytest.mark.asyncio
async def test_delete_me_idempotent(auth_user, db_session):
    """Second DELETE on an already-soft-deleted account returns 204 silently."""
    transport = ASGITransport(app=app)
    with (
        patch(
            "app.routers.users._fetch_auth_email",
            new=AsyncMock(return_value="bob@example.com"),
        ),
        patch(
            "app.routers.users._delete_supabase_auth_user",
            new=AsyncMock(return_value=None),
        ) as supa_mock,
    ):
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            r1 = await ac.delete("/api/users/me")
            r2 = await ac.delete("/api/users/me")

    assert r1.status_code == 204
    assert r2.status_code == 204
    # Le 2e appel ne doit PAS retoucher Supabase admin (déjà supprimé).
    assert supa_mock.await_count == 1


@pytest.mark.asyncio
async def test_delete_me_cascades_user_dependents(auth_user, db_session):
    """Cascade FK : preferences/interests are wiped when the profile is purged.

    The endpoint itself only soft-deletes (sets deleted_at) ; the hard delete
    is exercised via a manual purge to verify the CASCADE chain works with
    the test schema (Base.metadata.create_all reflects the model FKs).
    """
    # Insère 2 lignes dépendantes
    db_session.add(
        UserPreference(
            user_id=auth_user,
            preference_key="theme",
            preference_value="dark",
        )
    )
    db_session.add(UserInterest(user_id=auth_user, interest_slug="society", weight=1.0))
    await db_session.commit()

    transport = ASGITransport(app=app)
    with (
        patch(
            "app.routers.users._fetch_auth_email",
            new=AsyncMock(return_value="cascade@example.com"),
        ),
        patch(
            "app.routers.users._delete_supabase_auth_user",
            new=AsyncMock(return_value=None),
        ),
    ):
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            resp = await ac.delete("/api/users/me")
    assert resp.status_code == 204

    # Soft-delete : préférences/intérêts encore là (purgés par le cron à J+30)
    prefs = (
        await db_session.execute(
            select(UserPreference).where(UserPreference.user_id == auth_user)
        )
    ).all()
    assert len(prefs) == 1

    # Hard-delete via purge → cascade vide les dépendants
    from sqlalchemy import delete as sa_delete

    await db_session.execute(
        sa_delete(UserProfile).where(UserProfile.user_id == auth_user)
    )
    await db_session.commit()

    prefs_after = (
        await db_session.execute(
            select(UserPreference).where(UserPreference.user_id == auth_user)
        )
    ).all()
    interests_after = (
        await db_session.execute(
            select(UserInterest).where(UserInterest.user_id == auth_user)
        )
    ).all()
    assert prefs_after == []
    assert interests_after == []


@pytest.mark.asyncio
async def test_supabase_admin_404_silently_ignored(monkeypatch):
    """A 404 from Supabase admin must not raise — the function returns silently."""
    from app.routers import users as users_router

    # Force la config (sinon early-return en l'absence de service_role_key)
    monkeypatch.setattr(
        users_router,
        "get_settings",
        lambda: MagicMock(
            supabase_url="https://example.supabase.co",
            supabase_service_role_key="srv_key_xxx",
        ),
    )

    fake_response = MagicMock(status_code=404, text="not found")
    fake_client = MagicMock()
    fake_client.delete = AsyncMock(return_value=fake_response)
    fake_client.__aenter__ = AsyncMock(return_value=fake_client)
    fake_client.__aexit__ = AsyncMock(return_value=False)

    monkeypatch.setattr(
        users_router.httpx, "AsyncClient", lambda **_kwargs: fake_client
    )

    # Ne doit rien lever
    await users_router._delete_supabase_auth_user(
        "00000000-0000-0000-0000-000000000001"
    )
