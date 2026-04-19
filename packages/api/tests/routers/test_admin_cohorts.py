"""Tests for the admin cohorts endpoint (Story 14.1)."""

from unittest.mock import MagicMock, patch
from uuid import uuid4

import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app


@pytest.mark.asyncio
async def test_missing_header_returns_401_when_token_configured():
    user_id = uuid4()
    with patch("app.routers.admin_cohorts.get_settings") as mock_settings:
        mock_settings.return_value.admin_api_token = "s3cr3t"
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            resp = await ac.patch(
                f"/api/admin/users/{user_id}/cohorts",
                json={"acquisition_source": "waitlist"},
            )
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_wrong_header_returns_401():
    user_id = uuid4()
    with patch("app.routers.admin_cohorts.get_settings") as mock_settings:
        mock_settings.return_value.admin_api_token = "s3cr3t"
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            resp = await ac.patch(
                f"/api/admin/users/{user_id}/cohorts",
                json={"acquisition_source": "waitlist"},
                headers={"X-Admin-Token": "nope"},
            )
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_empty_token_config_returns_503():
    """Fail-closed when ADMIN_API_TOKEN is not configured."""
    user_id = uuid4()
    with patch("app.routers.admin_cohorts.get_settings") as mock_settings:
        mock_settings.return_value.admin_api_token = ""
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            resp = await ac.patch(
                f"/api/admin/users/{user_id}/cohorts",
                json={"acquisition_source": "waitlist"},
                headers={"X-Admin-Token": "anything"},
            )
    assert resp.status_code == 503


@pytest.mark.asyncio
async def test_invalid_acquisition_source_returns_422():
    user_id = uuid4()
    with patch("app.routers.admin_cohorts.get_settings") as mock_settings:
        mock_settings.return_value.admin_api_token = "s3cr3t"
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            resp = await ac.patch(
                f"/api/admin/users/{user_id}/cohorts",
                json={"acquisition_source": "not-a-valid-value"},
                headers={"X-Admin-Token": "s3cr3t"},
            )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_valid_request_calls_identify_and_commits():
    """End-to-end: token OK + valid body → identify + DB upsert attempted."""
    user_id = uuid4()

    mock_posthog = MagicMock()
    mock_posthog.enabled = True

    # Patch the DB session dep to a no-op session that just records writes.
    from app.database import get_db

    fake_session = MagicMock()

    async def _fake_execute(*args, **kwargs):
        result = MagicMock()
        result.scalar_one_or_none = MagicMock(return_value=None)
        return result

    fake_session.execute = _fake_execute
    fake_session.add = MagicMock()

    async def _fake_commit():
        return None

    fake_session.commit = _fake_commit

    async def _override_db():
        yield fake_session

    app.dependency_overrides[get_db] = _override_db

    try:
        with (
            patch("app.routers.admin_cohorts.get_settings") as mock_settings,
            patch(
                "app.routers.admin_cohorts.get_posthog_client",
                return_value=mock_posthog,
            ),
            patch(
                "app.routers.admin_cohorts.derive_cohort_properties",
                return_value={"is_creator_ytbeur": True, "is_close_to_laurin": False},
            ),
        ):
            mock_settings.return_value.admin_api_token = "s3cr3t"
            transport = ASGITransport(app=app)
            async with AsyncClient(transport=transport, base_url="http://test") as ac:
                resp = await ac.patch(
                    f"/api/admin/users/{user_id}/cohorts",
                    json={
                        "acquisition_source": "creator",
                        "email": "someone@youtube.com",
                    },
                    headers={"X-Admin-Token": "s3cr3t"},
                )
    finally:
        app.dependency_overrides.pop(get_db, None)

    assert resp.status_code == 200
    body = resp.json()
    assert body["acquisition_source"] == "creator"
    assert body["posthog_synced"] is True
    mock_posthog.identify.assert_called_once()
    identify_kwargs = mock_posthog.identify.call_args.kwargs
    assert identify_kwargs["properties"]["acquisition_source"] == "creator"
    assert identify_kwargs["properties"]["is_creator_ytbeur"] is True
