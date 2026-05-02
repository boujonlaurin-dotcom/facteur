"""Tests pour le router /api/veille (Story 18.1).

Couvre les endpoints CRUD config + suggestions + deliveries avec auth mockée.
LLM Mistral mocké via AsyncMock sur les singletons des suggesters.
"""

from unittest.mock import AsyncMock
from uuid import uuid4

import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from app.database import get_db
from app.dependencies import get_current_user_id
from app.main import app
from app.models.enums import SourceType
from app.models.source import Source
from app.models.user import UserProfile
from app.services.veille.source_suggester import (
    SourceSuggester,
    SourceSuggestionItem,
    SourceSuggestions,
)
from app.services.veille.topic_suggester import TopicSuggester


@pytest_asyncio.fixture
async def auth_user(db_session):
    user_id = uuid4()
    profile = UserProfile(
        user_id=user_id,
        display_name="Veille Route User",
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


@pytest_asyncio.fixture
async def curated_education_source(db_session):
    src = Source(
        id=uuid4(),
        name="Café Pédago",
        url="https://cafe.example.com",
        feed_url=f"https://cafe.example.com/feed-{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="education",
        is_active=True,
        is_curated=True,
    )
    db_session.add(src)
    await db_session.commit()
    return src


def _client():
    transport = ASGITransport(app=app)
    return AsyncClient(transport=transport, base_url="http://test")


class TestConfigCRUD:
    async def test_get_404_when_no_config(self, auth_user):
        async with _client() as ac:
            resp = await ac.get("/api/veille/config")
        assert resp.status_code == 404

    async def test_post_creates_config(self, auth_user, curated_education_source):
        body = {
            "theme_id": "education",
            "theme_label": "Éducation",
            "topics": [
                {
                    "topic_id": "t-eval",
                    "label": "Évaluations",
                    "kind": "preset",
                    "reason": None,
                    "position": 0,
                }
            ],
            "source_selections": [
                {
                    "kind": "followed",
                    "source_id": str(curated_education_source.id),
                    "position": 0,
                }
            ],
            "frequency": "weekly",
            "day_of_week": 0,
            "delivery_hour": 7,
            "timezone": "Europe/Paris",
        }
        async with _client() as ac:
            resp = await ac.post("/api/veille/config", json=body)

        assert resp.status_code == 200
        data = resp.json()
        assert data["theme_id"] == "education"
        assert data["frequency"] == "weekly"
        assert data["status"] == "active"
        assert len(data["topics"]) == 1
        assert data["topics"][0]["topic_id"] == "t-eval"
        assert len(data["sources"]) == 1
        assert data["sources"][0]["source"]["name"] == "Café Pédago"
        assert data["next_scheduled_at"] is not None

    async def test_post_upsert_replaces_topics(
        self, auth_user, curated_education_source
    ):
        base_body = {
            "theme_id": "education",
            "theme_label": "Éducation",
            "topics": [
                {
                    "topic_id": "t-eval",
                    "label": "Évaluations",
                    "kind": "preset",
                }
            ],
            "source_selections": [
                {
                    "kind": "followed",
                    "source_id": str(curated_education_source.id),
                }
            ],
            "frequency": "weekly",
            "day_of_week": 0,
            "delivery_hour": 7,
        }
        async with _client() as ac:
            await ac.post("/api/veille/config", json=base_body)

            updated = {
                **base_body,
                "topics": [
                    {
                        "topic_id": "t-neuro",
                        "label": "Neurosciences",
                        "kind": "suggested",
                        "reason": "Pertinent",
                    }
                ],
            }
            resp = await ac.post("/api/veille/config", json=updated)

        assert resp.status_code == 200
        data = resp.json()
        assert len(data["topics"]) == 1
        assert data["topics"][0]["topic_id"] == "t-neuro"

    async def test_patch_updates_frequency(self, auth_user, curated_education_source):
        async with _client() as ac:
            await ac.post(
                "/api/veille/config",
                json={
                    "theme_id": "education",
                    "theme_label": "Éducation",
                    "topics": [],
                    "source_selections": [
                        {
                            "kind": "followed",
                            "source_id": str(curated_education_source.id),
                        }
                    ],
                    "frequency": "weekly",
                    "day_of_week": 0,
                    "delivery_hour": 7,
                },
            )

            resp = await ac.patch(
                "/api/veille/config",
                json={"frequency": "monthly", "day_of_week": None},
            )

        assert resp.status_code == 200
        data = resp.json()
        assert data["frequency"] == "monthly"

    async def test_delete_archives(self, auth_user, curated_education_source):
        async with _client() as ac:
            await ac.post(
                "/api/veille/config",
                json={
                    "theme_id": "education",
                    "theme_label": "Éducation",
                    "topics": [],
                    "source_selections": [
                        {
                            "kind": "followed",
                            "source_id": str(curated_education_source.id),
                        }
                    ],
                    "frequency": "weekly",
                    "day_of_week": 0,
                    "delivery_hour": 7,
                },
            )

            resp = await ac.delete("/api/veille/config")
            assert resp.status_code == 204

            after = await ac.get("/api/veille/config")
            assert after.status_code == 404

    async def test_delete_idempotent(self, auth_user):
        async with _client() as ac:
            resp = await ac.delete("/api/veille/config")
        # Pas d'erreur même sans config (idempotent).
        assert resp.status_code == 204


class TestSuggestions:
    async def test_topics_returns_5(self, auth_user):
        from app.services.veille import topic_suggester as ts_module

        original = ts_module._topic_suggester
        mock_llm = AsyncMock()
        mock_llm.is_ready = True
        mock_llm.chat_json = AsyncMock(
            return_value={
                "topics": [
                    {"topic_id": f"t{i}", "label": f"T{i}", "reason": None}
                    for i in range(5)
                ]
            }
        )
        ts_module._topic_suggester = TopicSuggester(llm=mock_llm)
        try:
            async with _client() as ac:
                resp = await ac.post(
                    "/api/veille/suggestions/topics",
                    json={
                        "theme_id": "science",
                        "theme_label": "Science",
                        "selected_topic_ids": ["t-eval"],
                    },
                )
            assert resp.status_code == 200
            data = resp.json()
            assert len(data) == 5
            assert data[0]["topic_id"] == "t0"
        finally:
            ts_module._topic_suggester = original

    async def test_sources_followed_and_niche(
        self, auth_user, curated_education_source
    ):
        from app.services.veille import source_suggester as ss_module

        original = ss_module._source_suggester

        class StubSuggester(SourceSuggester):
            async def suggest_sources(  # type: ignore[override]
                self,
                session,
                user_id,
                theme_id,
                topic_labels,
                excluded_source_ids=None,
            ):
                return SourceSuggestions(
                    followed=[
                        SourceSuggestionItem(
                            source_id=curated_education_source.id,
                            name=curated_education_source.name,
                            url=curated_education_source.url,
                            feed_url=curated_education_source.feed_url,
                            theme="education",
                            why=None,
                        )
                    ],
                    niche=[],
                )

        ss_module._source_suggester = StubSuggester()
        try:
            async with _client() as ac:
                resp = await ac.post(
                    "/api/veille/suggestions/sources",
                    json={
                        "theme_id": "science",
                        "topic_labels": ["evaluations"],
                        "exclude_source_ids": [],
                    },
                )
            assert resp.status_code == 200
            data = resp.json()
            assert len(data["followed"]) == 1
            assert data["followed"][0]["name"] == "Café Pédago"
            assert data["niche"] == []
        finally:
            ss_module._source_suggester = original

    async def test_sources_invalid_theme_returns_422(self, auth_user):
        # Slug legacy / hors `ck_source_theme_valid` → 422 immédiat,
        # plus jamais 500 (qui empoisonnerait la session SQLAlchemy).
        async with _client() as ac:
            resp = await ac.post(
                "/api/veille/suggestions/sources",
                json={
                    "theme_id": "climat",
                    "topic_labels": ["climat"],
                    "exclude_source_ids": [],
                },
            )
        assert resp.status_code == 422

    async def test_topics_invalid_theme_returns_422(self, auth_user):
        async with _client() as ac:
            resp = await ac.post(
                "/api/veille/suggestions/topics",
                json={
                    "theme_id": "climat",
                    "theme_label": "Climat",
                    "selected_topic_ids": [],
                },
            )
        assert resp.status_code == 422


class TestDeliveries:
    async def test_list_empty_when_no_config(self, auth_user):
        async with _client() as ac:
            resp = await ac.get("/api/veille/deliveries")
        assert resp.status_code == 200
        assert resp.json() == []


class TestAuth:
    async def test_get_config_requires_auth(self, db_session):
        # Pas de auth_user fixture → pas d'override get_current_user_id.
        # FastAPI lèvera 401/403 (selon implementation auth).
        async with _client() as ac:
            resp = await ac.get("/api/veille/config")
        # 401 (Unauthorized) ou 403 (Forbidden) — on accepte les deux.
        assert resp.status_code in (401, 403)
