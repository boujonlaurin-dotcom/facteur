"""Tests pour les endpoints `/api/internal/*`.

Endpoint diagnostique ajouté après l'incident du 19 mai 2026 où spaCy n'était
plus installé dans l'image Railway. La chaîne `TitleAnnotationService`
dégradait silencieusement sans erreur visible côté client — d'où ce health
check explicite.
"""

from unittest.mock import AsyncMock, patch

import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from app.main import app
from tests.fixtures.fake_spacy import FakeDoc, FakeNlp, FakeToken, service_with_nlp

ADMIN_TOKEN = "s3cr3t"
ADMIN_HEADERS = {"X-Admin-Token": ADMIN_TOKEN}


@pytest_asyncio.fixture
async def client():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac


async def test_ner_health_without_admin_token_returns_401(client):
    with patch("app.routers.admin_cohorts.get_settings") as mock_settings:
        mock_settings.return_value.admin_api_token = "s3cr3t"
        response = await client.get("/api/internal/admin/ner-health")

    assert response.status_code == 401


async def test_ner_health_invalid_admin_token_returns_401(client):
    with patch("app.routers.admin_cohorts.get_settings") as mock_settings:
        mock_settings.return_value.admin_api_token = "s3cr3t"
        response = await client.get(
            "/api/internal/admin/ner-health",
            headers={"X-Admin-Token": "nope"},
        )

    assert response.status_code == 401


async def test_ner_health_without_configured_admin_token_returns_503(client):
    with patch("app.routers.admin_cohorts.get_settings") as mock_settings:
        mock_settings.return_value.admin_api_token = ""
        response = await client.get(
            "/api/internal/admin/ner-health",
            headers={"X-Admin-Token": "anything"},
        )

    assert response.status_code == 503


async def test_ner_health_reports_available_when_nlp_loaded(client):
    docs = {
        "Tsahal frappe Gaza": FakeDoc(
            tokens=[
                FakeToken("Tsahal", 0, "PROPN", "Tsahal"),
                FakeToken("frappe", 7, "VERB", "frapper"),
                FakeToken("Gaza", 14, "PROPN", "Gaza"),
            ],
        ),
    }
    fake_svc = service_with_nlp(FakeNlp(docs))

    with (
        patch("app.routers.admin_cohorts.get_settings") as mock_settings,
        patch(
            "app.routers.internal.get_title_annotation_service",
            return_value=fake_svc,
        ),
    ):
        mock_settings.return_value.admin_api_token = ADMIN_TOKEN
        response = await client.get(
            "/api/internal/admin/ner-health",
            params={"sample_title": "Tsahal frappe Gaza"},
            headers=ADMIN_HEADERS,
        )

    assert response.status_code == 200
    body = response.json()
    assert body["nlp_available"] is True
    assert body["model_version"] == "v2-spacy-fr_md"
    assert body["sample_title"] == "Tsahal frappe Gaza"
    token_texts = [t["text"] for t in body["sample_tokens"]]
    assert "Tsahal" in token_texts


async def test_ner_health_reports_unavailable_when_nlp_missing(client):
    fake_svc = service_with_nlp(None)

    with (
        patch("app.routers.admin_cohorts.get_settings") as mock_settings,
        patch(
            "app.routers.internal.get_title_annotation_service",
            return_value=fake_svc,
        ),
    ):
        mock_settings.return_value.admin_api_token = ADMIN_TOKEN
        response = await client.get(
            "/api/internal/admin/ner-health",
            headers=ADMIN_HEADERS,
        )

    assert response.status_code == 200
    body = response.json()
    assert body["nlp_available"] is False
    assert body["sample_tokens"] == []


async def test_internal_sync_with_valid_admin_token_reaches_handler(client):
    with (
        patch("app.routers.admin_cohorts.get_settings") as mock_settings,
        patch(
            "app.routers.internal.sync_all_sources",
            new=AsyncMock(return_value={"sources_synced": 2}),
        ) as mock_sync,
    ):
        mock_settings.return_value.admin_api_token = ADMIN_TOKEN
        response = await client.post(
            "/api/internal/sync",
            headers=ADMIN_HEADERS,
        )

    assert response.status_code == 200
    assert response.json()["results"] == {"sources_synced": 2}
    mock_sync.assert_awaited_once()
