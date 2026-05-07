"""Tests for the daily purge of soft-deleted user accounts (>30d)."""

from contextlib import asynccontextmanager
from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest

from app.jobs import purge_deleted_users as job_module
from app.models.user import UserInterest, UserProfile


@pytest.fixture
def patch_session_maker(monkeypatch, db_session):
    """Make safe_async_session() yield the test db_session (savepoint-isolated)."""

    @asynccontextmanager
    async def _maker():
        yield db_session

    monkeypatch.setattr(job_module, "safe_async_session", _maker)


@pytest.mark.asyncio
async def test_purge_skips_recent_deletions(db_session, patch_session_maker):
    user_id = uuid4()
    db_session.add(
        UserProfile(
            user_id=user_id,
            display_name=None,
            onboarding_completed=True,
            deleted_at=datetime.now(UTC) - timedelta(days=29),
        )
    )
    await db_session.commit()

    stats = await job_module.purge_deleted_users()

    assert stats["deleted_count"] == 0
    # User toujours là
    from sqlalchemy import select

    remaining = (
        await db_session.execute(
            select(UserProfile).where(UserProfile.user_id == user_id)
        )
    ).scalar_one_or_none()
    assert remaining is not None


@pytest.mark.asyncio
async def test_purge_removes_old_deletions_with_cascade(
    db_session, patch_session_maker
):
    user_id = uuid4()
    db_session.add(
        UserProfile(
            user_id=user_id,
            display_name=None,
            onboarding_completed=True,
            deleted_at=datetime.now(UTC) - timedelta(days=31),
        )
    )
    db_session.add(UserInterest(user_id=user_id, interest_slug="society", weight=1.0))
    await db_session.commit()

    stats = await job_module.purge_deleted_users()

    assert stats["deleted_count"] == 1
    from sqlalchemy import select

    profile = (
        await db_session.execute(
            select(UserProfile).where(UserProfile.user_id == user_id)
        )
    ).scalar_one_or_none()
    assert profile is None
    # Cascade : interests purgés
    interests = (
        await db_session.execute(
            select(UserInterest).where(UserInterest.user_id == user_id)
        )
    ).all()
    assert interests == []


@pytest.mark.asyncio
async def test_purge_ignores_non_soft_deleted(db_session, patch_session_maker):
    """Active users (deleted_at IS NULL) must never be touched."""
    user_id = uuid4()
    db_session.add(
        UserProfile(
            user_id=user_id,
            display_name="Active",
            onboarding_completed=True,
            deleted_at=None,
        )
    )
    await db_session.commit()

    stats = await job_module.purge_deleted_users()
    assert stats["deleted_count"] == 0
