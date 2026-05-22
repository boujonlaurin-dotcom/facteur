"""Tests pour `/api/internal/admin/ner-health`.

Endpoint diagnostique ajouté après l'incident du 19 mai 2026 où spaCy n'était
plus installé dans l'image Railway. La chaîne `TitleAnnotationService`
dégradait silencieusement sans erreur visible côté client — d'où ce health
check explicite.
"""

from unittest.mock import patch

import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from app.main import app
from tests.fixtures.fake_spacy import FakeDoc, FakeNlp, FakeToken, service_with_nlp


@pytest_asyncio.fixture
async def client():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac


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

    with patch(
        "app.routers.internal.get_title_annotation_service",
        return_value=fake_svc,
    ):
        response = await client.get(
            "/api/internal/admin/ner-health",
            params={"sample_title": "Tsahal frappe Gaza"},
        )

    assert response.status_code == 200
    body = response.json()
    assert body["nlp_available"] is True
    assert body["model_version"] == "v1-spacy-fr_md"
    assert body["sample_title"] == "Tsahal frappe Gaza"
    token_texts = [t["text"] for t in body["sample_tokens"]]
    assert "Tsahal" in token_texts


async def test_ner_health_reports_unavailable_when_nlp_missing(client):
    fake_svc = service_with_nlp(None)

    with patch(
        "app.routers.internal.get_title_annotation_service",
        return_value=fake_svc,
    ):
        response = await client.get("/api/internal/admin/ner-health")

    assert response.status_code == 200
    body = response.json()
    assert body["nlp_available"] is False
    assert body["sample_tokens"] == []
