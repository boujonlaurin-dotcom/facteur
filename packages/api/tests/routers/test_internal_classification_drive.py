"""Tests pour /api/internal/admin/classification/drive (force-drive).

Endpoint de pilotage manuel ajouté avec l'observabilité worker (incident
2026-06-30) : déclenche `ClassificationWorker.drive_once()` hors run-loop pour
vérifier/débugger le pipeline post-deploy si le worker refuse de tourner.
Gaté `require_admin_token`.
"""

from unittest.mock import AsyncMock, MagicMock, patch

import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from app.database import get_db
from app.main import app

ADMIN_TOKEN = "s3cr3t"
ADMIN_HEADERS = {"X-Admin-Token": ADMIN_TOKEN}


@pytest_asyncio.fixture
async def client(db_session):
    async def _fake_db():
        yield db_session

    app.dependency_overrides[get_db] = _fake_db
    transport = ASGITransport(app=app)
    try:
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            yield ac
    finally:
        app.dependency_overrides.pop(get_db, None)


async def test_drive_without_admin_token_returns_401(client):
    with patch("app.routers.admin_cohorts.get_settings") as mock_settings:
        mock_settings.return_value.admin_api_token = ADMIN_TOKEN
        resp = await client.post("/api/internal/admin/classification/drive")
    assert resp.status_code == 401


async def test_drive_with_admin_token_runs_one_batch(client):
    fake_worker = MagicMock()
    fake_worker.drive_once = AsyncMock(return_value=5)

    with (
        patch("app.routers.admin_cohorts.get_settings") as mock_settings,
        patch(
            "app.workers.classification_worker.get_worker",
            return_value=fake_worker,
        ),
    ):
        mock_settings.return_value.admin_api_token = ADMIN_TOKEN
        resp = await client.post(
            "/api/internal/admin/classification/drive",
            headers=ADMIN_HEADERS,
        )

    assert resp.status_code == 200
    body = resp.json()
    assert body["dequeued"] == 5
    # File vide dans le harness → pending_before == 0, remonté sans erreur.
    assert body["pending_before"] == 0
    fake_worker.drive_once.assert_awaited_once()
