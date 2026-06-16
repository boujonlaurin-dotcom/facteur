"""Tests endpoint `POST /personalization/topics/` — parent explicite `slug_parent`.

Couvre le plan QA onboarding (partie 2) :
- un `slug_parent` fourni par l'UI/onboarding prime sur celui deviné par le LLM ;
- un `slug_parent` invalide est rejeté (422) ;
- un même sujet (nom + parent) n'est jamais dupliqué (idempotent), et conserve
  son parent explicite.
"""

from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import func, select

from app.database import get_db
from app.dependencies import get_current_user_id
from app.main import app
from app.models.user_topic_profile import UserTopicProfile
from app.services.ml.topic_enrichment_service import TopicEnrichmentResult


def _enrichment_service(
    *, slug_parent: str = "society", entity_type=None, canonical_name=None
):
    """Mock du service d'enrichissement LLM avec un `slug_parent` deviné fixe."""
    svc = MagicMock()
    svc.enrich = AsyncMock(
        return_value=TopicEnrichmentResult(
            slug_parent=slug_parent,
            keywords=["mot1", "mot2"],
            intent_description="Description de suivi",
            entity_type=entity_type,
            canonical_name=canonical_name,
        )
    )
    return svc


@pytest_asyncio.fixture
async def client_with_user(db_session):
    """Client HTTP avec auth bypass + `get_db` câblé sur la session de test."""
    user_id = uuid4()

    async def _fake_user() -> str:
        return str(user_id)

    async def _fake_db():
        yield db_session

    app.dependency_overrides[get_current_user_id] = _fake_user
    app.dependency_overrides[get_db] = _fake_db
    transport = ASGITransport(app=app)
    try:
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            yield ac, user_id, db_session
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)
        app.dependency_overrides.pop(get_db, None)


@pytest.mark.asyncio
async def test_explicit_slug_parent_overrides_llm(client_with_user):
    """`name=Tennis, slug_parent=sport` → slug_parent=sport (le LLM devinait autre)."""
    ac, _user_id, _db = client_with_user
    with patch(
        "app.routers.custom_topics.get_topic_enrichment_service",
        return_value=_enrichment_service(slug_parent="society"),
    ):
        resp = await ac.post(
            "/api/personalization/topics/",
            json={"name": "Tennis", "slug_parent": "sport"},
        )
    assert resp.status_code == 201
    assert resp.json()["slug_parent"] == "sport"


@pytest.mark.asyncio
async def test_llm_slug_used_when_no_explicit_parent(client_with_user):
    """Sans `slug_parent`, on retombe sur le slug deviné par le LLM."""
    ac, _user_id, _db = client_with_user
    with patch(
        "app.routers.custom_topics.get_topic_enrichment_service",
        return_value=_enrichment_service(slug_parent="ai"),
    ):
        resp = await ac.post(
            "/api/personalization/topics/",
            json={"name": "Modèles de langage"},
        )
    assert resp.status_code == 201
    assert resp.json()["slug_parent"] == "ai"


@pytest.mark.asyncio
async def test_invalid_slug_parent_rejected(client_with_user):
    """Un `slug_parent` hors `VALID_TOPIC_SLUGS` est refusé (422)."""
    ac, _user_id, _db = client_with_user
    with patch(
        "app.routers.custom_topics.get_topic_enrichment_service",
        return_value=_enrichment_service(),
    ):
        resp = await ac.post(
            "/api/personalization/topics/",
            json={"name": "Tennis", "slug_parent": "pas-un-slug"},
        )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_duplicate_topic_is_idempotent_and_keeps_parent(client_with_user):
    """`name=Biologie, slug_parent=science` deux fois → 1 seule ligne, slug=science."""
    ac, user_id, db = client_with_user
    with patch(
        "app.routers.custom_topics.get_topic_enrichment_service",
        # Le LLM devinerait "society" — l'explicite "science" doit être conservé
        # et la 2e tentative ne doit pas créer de doublon incohérent.
        return_value=_enrichment_service(slug_parent="society"),
    ):
        r1 = await ac.post(
            "/api/personalization/topics/",
            json={"name": "Biologie", "slug_parent": "science"},
        )
        r2 = await ac.post(
            "/api/personalization/topics/",
            json={"name": "biologie", "slug_parent": "science"},
        )

    assert r1.status_code == 201
    assert r1.json()["slug_parent"] == "science"
    # Idempotent : même sujet (nom insensible à la casse + parent) → renvoie l'existant.
    assert r2.json()["slug_parent"] == "science"

    count = await db.scalar(
        select(func.count())
        .select_from(UserTopicProfile)
        .where(UserTopicProfile.user_id == user_id)
    )
    assert count == 1, "aucun doublon ne doit être créé pour le même sujet/parent"
