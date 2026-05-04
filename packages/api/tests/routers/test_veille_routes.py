"""Tests pour le router /api/veille (Story 18.1).

Couvre les endpoints CRUD config + suggestions + deliveries avec auth mockée.
LLM Mistral mocké via AsyncMock sur les singletons des suggesters.
"""

from datetime import UTC, datetime, timedelta
from unittest.mock import AsyncMock
from uuid import uuid4

import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from app.database import get_db
from app.dependencies import get_current_user_id
from app.main import app
from app.models.content import Content
from app.models.enums import ContentType, SourceType
from app.models.source import Source
from app.models.user import UserProfile
from app.models.veille import (
    VeilleConfig,
    VeilleDelivery,
    VeilleGenerationState,
    VeilleStatus,
)
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

    async def test_post_persists_purpose_and_brief(
        self, auth_user, curated_education_source
    ):
        body = {
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
            "purpose": "preparer_projet",
            "purpose_other": None,
            "editorial_brief": "Plutôt analyses long format que breaking news",
            "preset_id": "ia_agentique",
        }
        async with _client() as ac:
            resp = await ac.post("/api/veille/config", json=body)
            assert resp.status_code == 200
            data = resp.json()
            assert data["purpose"] == "preparer_projet"
            assert data["purpose_other"] is None
            assert (
                data["editorial_brief"]
                == "Plutôt analyses long format que breaking news"
            )
            assert data["preset_id"] == "ia_agentique"

            # GET re-confirme la persistance.
            after = await ac.get("/api/veille/config")
            assert after.status_code == 200
            data2 = after.json()
            assert data2["purpose"] == "preparer_projet"
            assert (
                data2["editorial_brief"]
                == "Plutôt analyses long format que breaking news"
            )
            assert data2["preset_id"] == "ia_agentique"

            # Update : on peut clear le brief en envoyant null.
            update = {
                **body,
                "editorial_brief": None,
                "purpose": "autre",
                "purpose_other": "veille perso",
            }
            resp2 = await ac.post("/api/veille/config", json=update)
            assert resp2.status_code == 200
            data3 = resp2.json()
            assert data3["purpose"] == "autre"
            assert data3["purpose_other"] == "veille perso"
            assert data3["editorial_brief"] is None

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
                purpose=None,
                purpose_other=None,
                editorial_brief=None,
            ):
                return SourceSuggestions(
                    sources=[
                        SourceSuggestionItem(
                            source_id=curated_education_source.id,
                            name=curated_education_source.name,
                            url=curated_education_source.url,
                            feed_url=curated_education_source.feed_url,
                            theme="education",
                            why=None,
                            is_already_followed=True,
                            relevance_score=0.9,
                        )
                    ],
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
            assert len(data["sources"]) == 1
            assert data["sources"][0]["name"] == "Café Pédago"
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

    async def test_sources_db_error_returns_503(self, auth_user):
        """T2 — SQLAlchemyError pendant suggest/commit → 503 propre, pas 500."""
        from sqlalchemy.exc import OperationalError

        from app.services.veille import source_suggester as ss_module

        original = ss_module._source_suggester

        class FailingSuggester(SourceSuggester):
            async def suggest_sources(  # type: ignore[override]
                self, *_a, **_kw
            ):
                raise OperationalError("INSERT", {}, Exception("EDBHANDLEREXITED"))

        ss_module._source_suggester = FailingSuggester()
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
            assert resp.status_code == 503
            assert "indisponible" in resp.json()["detail"].lower()
        finally:
            ss_module._source_suggester = original

    async def test_sources_llm_timeout_returns_503(self, auth_user):
        """T2 — httpx.TimeoutException du LLM → 503 propre."""
        import httpx

        from app.services.veille import source_suggester as ss_module

        original = ss_module._source_suggester

        class TimeoutSuggester(SourceSuggester):
            async def suggest_sources(  # type: ignore[override]
                self, *_a, **_kw
            ):
                raise httpx.TimeoutException("LLM timed out")

        ss_module._source_suggester = TimeoutSuggester()
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
            assert resp.status_code == 503
            assert "llm" in resp.json()["detail"].lower()
        finally:
            ss_module._source_suggester = original

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


@pytest_asyncio.fixture
async def active_veille_config(db_session, auth_user):
    cfg = VeilleConfig(
        id=uuid4(),
        user_id=auth_user,
        theme_id="education",
        theme_label="Éducation",
        frequency="weekly",
        day_of_week=0,
        delivery_hour=7,
        timezone="Europe/Paris",
        status=VeilleStatus.ACTIVE.value,
    )
    db_session.add(cfg)
    await db_session.commit()
    return cfg


class TestGenerateFirstDelivery:
    async def test_creates_pending_delivery(
        self, monkeypatch, auth_user, active_veille_config
    ):
        # Empêche le BackgroundTask de toucher le LLM réel.
        from app.routers import veille as veille_module

        bg_calls: list[tuple] = []

        def _capture_add_task(self, func, *args, **kwargs):
            bg_calls.append((func, args, kwargs))

        monkeypatch.setattr(
            "fastapi.BackgroundTasks.add_task",
            _capture_add_task,
            raising=True,
        )

        async with _client() as ac:
            resp = await ac.post("/api/veille/deliveries/generate-first")

        assert resp.status_code == 202
        body = resp.json()
        assert body["estimated_seconds"] == 60
        assert body["delivery_id"] is not None

        # BackgroundTask scheduled avec _run_first_delivery_with_retry.
        assert any(
            call[0] is veille_module._run_first_delivery_with_retry for call in bg_calls
        ), bg_calls

    async def test_refuses_when_delivery_exists(
        self, db_session, auth_user, active_veille_config
    ):
        existing = VeilleDelivery(
            id=uuid4(),
            veille_config_id=active_veille_config.id,
            target_date=datetime.now(UTC).date(),
            generation_state=VeilleGenerationState.SUCCEEDED.value,
        )
        db_session.add(existing)
        await db_session.commit()

        async with _client() as ac:
            resp = await ac.post("/api/veille/deliveries/generate-first")

        assert resp.status_code == 403

    async def test_refuses_when_no_config(self, auth_user):
        async with _client() as ac:
            resp = await ac.post("/api/veille/deliveries/generate-first")
        assert resp.status_code == 404


class TestSourceExamples:
    async def test_returns_two_most_recent_from_db(
        self, db_session, auth_user, curated_education_source
    ):
        # Reset le cache module-level pour isoler le test.
        from app.routers.veille import _SOURCE_EXAMPLES_CACHE

        _SOURCE_EXAMPLES_CACHE.clear()

        now = datetime.now(UTC)
        for i in range(3):
            db_session.add(
                Content(
                    id=uuid4(),
                    source_id=curated_education_source.id,
                    title=f"Article {i}",
                    url=f"https://example.com/a{i}",
                    description=f"Excerpt {i}",
                    published_at=now - timedelta(days=i),
                    content_type=ContentType.ARTICLE,
                    guid=f"g{i}",
                )
            )
        await db_session.commit()

        async with _client() as ac:
            resp = await ac.get(
                f"/api/veille/sources/{curated_education_source.id}/examples"
            )
        assert resp.status_code == 200
        data = resp.json()
        assert len(data) == 2
        assert data[0]["title"] == "Article 0"
        assert data[1]["title"] == "Article 1"
        assert data[0]["url"] == "https://example.com/a0"
        assert data[0]["excerpt"] == "Excerpt 0"

    async def test_falls_back_to_rss_when_db_empty(
        self, monkeypatch, auth_user, curated_education_source
    ):
        from app.routers.veille import _SOURCE_EXAMPLES_CACHE

        _SOURCE_EXAMPLES_CACHE.clear()

        fake_feed = {
            "entries": [
                {
                    "title": "Niche Article 1",
                    "link": "https://niche.example.com/1",
                    "summary": "Summary 1",
                    "published_parsed": (2026, 4, 28, 9, 0, 0, 0, 118, 0),
                },
                {
                    "title": "Niche Article 2",
                    "link": "https://niche.example.com/2",
                    "summary": "Summary 2",
                    "published_parsed": (2026, 4, 27, 9, 0, 0, 0, 117, 0),
                },
            ]
        }

        async def fake_parse(self, url):
            return fake_feed

        async def fake_close(self):
            return None

        from app.services.rss_parser import RSSParser

        monkeypatch.setattr(RSSParser, "parse", fake_parse)
        monkeypatch.setattr(RSSParser, "close", fake_close)

        async with _client() as ac:
            resp = await ac.get(
                f"/api/veille/sources/{curated_education_source.id}/examples"
            )

        assert resp.status_code == 200
        data = resp.json()
        assert len(data) == 2
        assert data[0]["title"] == "Niche Article 1"
        assert data[0]["url"] == "https://niche.example.com/1"

    async def test_returns_empty_when_rss_fails(
        self, monkeypatch, auth_user, curated_education_source
    ):
        from app.routers.veille import _SOURCE_EXAMPLES_CACHE

        _SOURCE_EXAMPLES_CACHE.clear()

        async def fake_parse(self, url):
            raise ValueError("RSS unreachable")

        async def fake_close(self):
            return None

        from app.services.rss_parser import RSSParser

        monkeypatch.setattr(RSSParser, "parse", fake_parse)
        monkeypatch.setattr(RSSParser, "close", fake_close)

        async with _client() as ac:
            resp = await ac.get(
                f"/api/veille/sources/{curated_education_source.id}/examples"
            )

        assert resp.status_code == 200
        assert resp.json() == []
