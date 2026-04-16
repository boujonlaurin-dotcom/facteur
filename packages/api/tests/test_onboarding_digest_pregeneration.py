"""Regression tests for the new-user onboarding → digest loading fix.

Cf. docs/bugs/bug-onboarding-digest-loading.md.

Before this fix:
1. `POST /users/onboarding` didn't trigger digest generation — new users who
   finished onboarding outside the 6h Paris batch window waited until the
   next morning to see any digest.
2. `GET /digest` and `GET /digest/both` returned 503 (or 200 with null
   variants) when the on-demand pipeline produced no items for a user without
   history — the mobile client ran out of retry budget and showed an infinite
   spinner.

These tests lock in:
1. Onboarding endpoint schedules initial digest generation via BackgroundTasks.
2. `GET /digest` returns 202 (not 503) when `get_or_create_digest` returns None,
   with a background regen scheduled.
3. `GET /digest/both` returns 202 (not a 200 with null fields) when both
   variants come back empty, with regen scheduled for both variants.
"""

from datetime import UTC, datetime
from unittest.mock import AsyncMock, patch
from uuid import uuid4

import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app
from app.schemas.user import OnboardingResponse, UserProfileResponse


@pytest.mark.asyncio
async def test_digest_returns_202_when_service_returns_none_and_schedules_regen():
    """Single-variant endpoint must return 202 + schedule regen, not 503."""
    from app.database import get_db
    from app.dependencies import get_current_user_id

    fake_user_id = str(uuid4())

    async def _fake_user():
        return fake_user_id

    class _FakeDB:
        async def scalar(self, *args, **kwargs):
            return None

    async def _fake_db():
        yield _FakeDB()

    app.dependency_overrides[get_current_user_id] = _fake_user
    app.dependency_overrides[get_db] = _fake_db

    try:
        with (
            patch(
                "app.routers.digest.is_generation_running", return_value=False
            ),
            patch(
                "app.routers.digest.DigestService.get_or_create_digest",
                new=AsyncMock(return_value=None),
            ),
            patch("app.routers.digest.schedule_digest_regen") as mock_regen,
        ):
            transport = ASGITransport(app=app)
            async with AsyncClient(
                transport=transport, base_url="http://test", timeout=5.0
            ) as ac:
                resp = await ac.get("/api/digest")
    finally:
        app.dependency_overrides.clear()

    assert resp.status_code == 202, (
        f"Empty digest must surface as 202 (polling contract), not 503 "
        f"(which exhausts mobile retry budget). Got {resp.status_code}: "
        f"{resp.text[:200]}"
    )
    body = resp.json()
    assert body.get("status") == "preparing", body
    mock_regen.assert_called_once()


@pytest.mark.asyncio
async def test_digest_both_returns_202_when_both_variants_none():
    """Dual endpoint must not return 200 with null variants — the mobile
    client mishandles that as a permanent failure."""
    from app.database import get_db
    from app.dependencies import get_current_user_id

    fake_user_id = str(uuid4())

    async def _fake_user():
        return fake_user_id

    class _FakeDB:
        async def scalar(self, *args, **kwargs):
            return None

    async def _fake_db():
        yield _FakeDB()

    app.dependency_overrides[get_current_user_id] = _fake_user
    app.dependency_overrides[get_db] = _fake_db

    try:
        with (
            patch(
                "app.routers.digest.is_generation_running", return_value=False
            ),
            patch(
                "app.routers.digest.DigestService.get_or_create_digest",
                new=AsyncMock(return_value=None),
            ),
            patch("app.routers.digest.schedule_digest_regen") as mock_regen,
        ):
            transport = ASGITransport(app=app)
            async with AsyncClient(
                transport=transport, base_url="http://test", timeout=5.0
            ) as ac:
                resp = await ac.get("/api/digest/both")
    finally:
        app.dependency_overrides.clear()

    assert resp.status_code == 202, (
        f"Both variants None must surface as 202, got {resp.status_code}: "
        f"{resp.text[:200]}"
    )
    body = resp.json()
    assert body.get("status") == "preparing", body
    # Both variants scheduled for regen (normal + serein)
    assert mock_regen.call_count == 2, (
        f"Expected 2 regen calls (normal + serein), got {mock_regen.call_count}"
    )


@pytest.mark.asyncio
async def test_onboarding_schedules_initial_digest_generation():
    """Completing onboarding must enqueue a background task to pre-warm the
    digest during the 10s mobile conclusion animation."""
    from app.database import get_db
    from app.dependencies import get_current_user_id

    fake_user_id = str(uuid4())

    async def _fake_user():
        return fake_user_id

    class _FakeDB:
        async def execute(self, *args, **kwargs):
            class _R:
                def scalars(self_inner):
                    class _S:
                        def all(self_inner2):
                            return []
                    return _S()
            return _R()
        async def flush(self):
            return None
        def add(self, *args, **kwargs):
            return None
        async def scalar(self, *args, **kwargs):
            return None

    async def _fake_db():
        yield _FakeDB()

    app.dependency_overrides[get_current_user_id] = _fake_user
    app.dependency_overrides[get_db] = _fake_db

    now = datetime.now(UTC)
    fake_profile = UserProfileResponse(
        id=uuid4(),
        user_id=uuid4(),
        display_name=None,
        age_range="25-34",
        gender="other",
        onboarding_completed=True,
        gamification_enabled=True,
        weekly_goal=5,
        created_at=now,
        updated_at=now,
    )
    fake_response = OnboardingResponse(
        profile=fake_profile,
        interests_created=3,
        subtopics_created=2,
        preferences_created=5,
        sources_created=4,
        sources_removed=0,
    )
    fake_result = {
        "profile": fake_profile,
        "interests_created": 3,
        "subtopics_created": 2,
        "preferences_created": 5,
        "sources_created": 4,
        "sources_removed": 0,
    }

    # Payload must include all required OnboardingAnswers fields (objective,
    # approach, response_style) so the request doesn't 422 before reaching the
    # handler — otherwise the schedule assertion would be silently skipped.
    # camelCase keys because OnboardingAnswers uses an alias_generator.
    valid_payload = {
        "answers": {
            "objective": "learn",
            "approach": "direct",
            "responseStyle": "decisive",
            "ageRange": "25-34",
            "gender": "other",
            "gamificationEnabled": True,
            "weeklyGoal": 5,
            "themes": ["tech"],
            "subtopics": [],
            "preferredSources": [],
        }
    }

    try:
        with (
            patch(
                "app.routers.users.UserService.save_onboarding",
                new=AsyncMock(return_value=fake_result),
            ),
            patch(
                "app.routers.users.OnboardingResponse.model_validate",
                return_value=fake_response,
            ),
            patch(
                "app.routers.users.schedule_initial_digest_generation"
            ) as mock_schedule,
        ):
            transport = ASGITransport(app=app)
            async with AsyncClient(
                transport=transport, base_url="http://test", timeout=5.0
            ) as ac:
                resp = await ac.post("/api/users/onboarding", json=valid_payload)
    finally:
        app.dependency_overrides.clear()

    # Strict assertion: if the endpoint doesn't 200, the BackgroundTask never
    # ran and new users will fall back to waiting for the next 6 AM batch.
    assert resp.status_code == 200, (
        f"Expected 200, got {resp.status_code}: {resp.text[:300]}"
    )
    mock_schedule.assert_called_once()
    # Called with the user UUID (positional arg from routers/users.py)
    called_args, _ = mock_schedule.call_args
    assert str(called_args[0]) == fake_user_id, (
        f"Scheduler called with {called_args[0]}, expected {fake_user_id}"
    )
