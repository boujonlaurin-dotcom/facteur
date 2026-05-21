"""Tests pour le router /api/veille (Story 23.1).

Couvre les endpoints refondus en filtre temps-réel :
- GET / POST / DELETE /config (avec keywords[])
- GET /feed (matching OR thèmes/topics/sources/keywords + boost source)
- 410 Gone shim sur /suggestions/* et /deliveries/* (clients legacy)
"""

from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from sqlalchemy import select

from app.database import get_db
from app.dependencies import get_current_user_id
from app.main import app
from app.models.content import Content
from app.models.enums import ContentType, SourceType
from app.models.source import Source
from app.models.user import UserProfile
from app.models.user_favorites import UserFavoriteInterest
from app.models.veille import VeilleConfig, VeilleStatus


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
async def curated_tech_source(db_session):
    src = Source(
        id=uuid4(),
        name="Tech Daily",
        url="https://tech.example.com",
        feed_url=f"https://tech.example.com/feed-{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="tech",
        is_active=True,
        is_curated=True,
    )
    db_session.add(src)
    await db_session.commit()
    return src


@pytest_asyncio.fixture
async def tech_content(db_session, curated_tech_source):
    """3 articles tech : un matche le thème, un matche keyword 'ia', un matche les deux."""
    items = [
        Content(
            id=uuid4(),
            source_id=curated_tech_source.id,
            title="GPT-5 dévoilé : nouvelle génération d'IA",
            url="https://tech.example.com/gpt5",
            description="OpenAI annonce GPT-5",
            published_at=datetime.now(UTC) - timedelta(hours=1),
            content_type=ContentType.ARTICLE,
            guid=f"gpt5-{uuid4()}",
            theme="tech",
            topics=["ai", "openai"],
        ),
        Content(
            id=uuid4(),
            source_id=curated_tech_source.id,
            title="Bourse en hausse de 3%",
            url="https://tech.example.com/bourse",
            description="Les marchés progressent",
            published_at=datetime.now(UTC) - timedelta(hours=2),
            content_type=ContentType.ARTICLE,
            guid=f"bourse-{uuid4()}",
            theme="economy",
            topics=["markets"],
        ),
        Content(
            id=uuid4(),
            source_id=curated_tech_source.id,
            title="Vélo électrique nouveau modèle",
            url="https://tech.example.com/velo",
            description="Test du nouveau VAE Decathlon",
            published_at=datetime.now(UTC) - timedelta(hours=3),
            content_type=ContentType.ARTICLE,
            guid=f"velo-{uuid4()}",
            theme="society",
            topics=["mobility"],
        ),
    ]
    db_session.add_all(items)
    await db_session.commit()
    return items


def _client() -> AsyncClient:
    return AsyncClient(transport=ASGITransport(app=app), base_url="http://test")


class TestConfigCRUD:
    async def test_get_config_404_when_none(self, auth_user):
        async with _client() as c:
            r = await c.get("/api/veille/config")
        assert r.status_code == 404

    async def test_post_config_creates_with_keywords(
        self, auth_user, curated_tech_source
    ):
        payload = {
            "theme_id": "tech",
            "theme_label": "Tech",
            "topics": [
                {
                    "topic_id": "ai",
                    "label": "IA",
                    "kind": "preset",
                    "position": 0,
                }
            ],
            "source_selections": [
                {
                    "kind": "followed",
                    "source_id": str(curated_tech_source.id),
                    "position": 0,
                }
            ],
            "keywords": [
                {"keyword": "Intelligence Artificielle", "position": 0},
                {"keyword": "machine learning", "position": 1},
            ],
        }
        async with _client() as c:
            r = await c.post("/api/veille/config", json=payload)

        assert r.status_code == 200, r.text
        data = r.json()
        assert data["theme_id"] == "tech"
        assert len(data["topics"]) == 1
        assert len(data["sources"]) == 1
        assert len(data["keywords"]) == 2
        assert data["keywords"][0]["keyword"] == "intelligence artificielle"

    async def test_post_config_requires_at_least_one_axis(self, auth_user):
        payload = {
            "theme_id": "tech",
            "theme_label": "Tech",
            "topics": [],
            "source_selections": [],
            "keywords": [],
        }
        async with _client() as c:
            r = await c.post("/api/veille/config", json=payload)
        assert r.status_code == 422

    async def test_post_config_keywords_max_20(self, auth_user):
        payload = {
            "theme_id": "tech",
            "theme_label": "Tech",
            "keywords": [
                {"keyword": f"keyword-{i}", "position": i} for i in range(21)
            ],
        }
        async with _client() as c:
            r = await c.post("/api/veille/config", json=payload)
        assert r.status_code == 422

    async def test_delete_config_idempotent(self, auth_user, curated_tech_source):
        payload = {
            "theme_id": "tech",
            "theme_label": "Tech",
            "source_selections": [
                {"kind": "followed", "source_id": str(curated_tech_source.id)}
            ],
        }
        async with _client() as c:
            create = await c.post("/api/veille/config", json=payload)
            assert create.status_code == 200
            d1 = await c.delete("/api/veille/config")
            d2 = await c.delete("/api/veille/config")
        assert d1.status_code == 204
        assert d2.status_code == 204


class TestFavoriteIntegration:
    """Story 23.1 PR-3 : POST /config crée un favori, DELETE /config le retire."""

    async def _favorites(self, db_session, user_id):
        rows = (
            await db_session.execute(
                select(UserFavoriteInterest).where(
                    UserFavoriteInterest.user_id == user_id
                )
            )
        ).scalars().all()
        return list(rows)

    async def test_post_config_auto_creates_favorite(
        self, auth_user, curated_tech_source, db_session
    ):
        payload = {
            "theme_id": "tech",
            "theme_label": "Tech",
            "source_selections": [
                {"kind": "followed", "source_id": str(curated_tech_source.id)}
            ],
        }
        async with _client() as c:
            r = await c.post("/api/veille/config", json=payload)
        assert r.status_code == 200
        cfg_id = r.json()["id"]

        favs = await self._favorites(db_session, auth_user)
        assert len(favs) == 1
        assert str(favs[0].veille_config_id) == cfg_id
        assert favs[0].position == 0
        assert favs[0].interest_slug is None
        assert favs[0].custom_topic_id is None

    async def test_post_config_idempotent_favorite(
        self, auth_user, curated_tech_source, db_session
    ):
        payload = {
            "theme_id": "tech",
            "theme_label": "Tech",
            "source_selections": [
                {"kind": "followed", "source_id": str(curated_tech_source.id)}
            ],
        }
        async with _client() as c:
            await c.post("/api/veille/config", json=payload)
            await c.post("/api/veille/config", json=payload)

        favs = await self._favorites(db_session, auth_user)
        assert len(favs) == 1
        assert favs[0].position == 0

    async def test_post_config_favorite_appended_when_others_exist(
        self, auth_user, curated_tech_source, db_session
    ):
        db_session.add(
            UserFavoriteInterest(
                user_id=auth_user, position=0, interest_slug="tech"
            )
        )
        db_session.add(
            UserFavoriteInterest(
                user_id=auth_user, position=1, interest_slug="society"
            )
        )
        await db_session.commit()

        payload = {
            "theme_id": "tech",
            "theme_label": "Tech",
            "source_selections": [
                {"kind": "followed", "source_id": str(curated_tech_source.id)}
            ],
        }
        async with _client() as c:
            r = await c.post("/api/veille/config", json=payload)
        assert r.status_code == 200

        favs = sorted(
            await self._favorites(db_session, auth_user), key=lambda f: f.position
        )
        assert len(favs) == 3
        assert favs[2].position == 2
        assert favs[2].veille_config_id is not None

    async def test_delete_config_removes_favorite_in_same_tx(
        self, auth_user, curated_tech_source, db_session
    ):
        payload = {
            "theme_id": "tech",
            "theme_label": "Tech",
            "source_selections": [
                {"kind": "followed", "source_id": str(curated_tech_source.id)}
            ],
        }
        async with _client() as c:
            create = await c.post("/api/veille/config", json=payload)
            assert create.status_code == 200
            cfg_id = create.json()["id"]
            d = await c.delete("/api/veille/config")
        assert d.status_code == 204

        favs = await self._favorites(db_session, auth_user)
        assert favs == []

        cfg = (
            await db_session.execute(
                select(VeilleConfig).where(VeilleConfig.id == cfg_id)
            )
        ).scalar_one()
        assert cfg.status == VeilleStatus.ARCHIVED.value

    async def test_delete_config_idempotent_when_no_favorite_row(
        self, auth_user, db_session
    ):
        async with _client() as c:
            d = await c.delete("/api/veille/config")
        assert d.status_code == 204

        favs = await self._favorites(db_session, auth_user)
        assert favs == []


class TestFeed:
    async def test_feed_empty_when_no_config(self, auth_user):
        async with _client() as c:
            r = await c.get("/api/veille/feed")
        assert r.status_code == 200
        assert r.json()["items"] == []

    async def test_feed_matches_theme(
        self, auth_user, curated_tech_source, tech_content
    ):
        payload = {
            "theme_id": "tech",
            "theme_label": "Tech",
            "source_selections": [
                {"kind": "followed", "source_id": str(curated_tech_source.id)}
            ],
        }
        async with _client() as c:
            await c.post("/api/veille/config", json=payload)
            r = await c.get("/api/veille/feed?limit=20")
        assert r.status_code == 200
        data = r.json()
        # 3 articles, mais la source matche pour les 3 → tous reviennent (source axe)
        assert len(data["items"]) == 3
        # GPT-5 matche aussi theme=tech
        gpt = next(it for it in data["items"] if "GPT-5" in it["title"])
        assert "theme" in gpt["matched_on"]
        assert "source" in gpt["matched_on"]

    async def test_feed_matches_keyword(
        self, auth_user, curated_tech_source, tech_content
    ):
        payload = {
            "theme_id": "tech",
            "theme_label": "Tech",
            "keywords": [{"keyword": "vélo"}],
        }
        async with _client() as c:
            await c.post("/api/veille/config", json=payload)
            r = await c.get("/api/veille/feed")
        items = r.json()["items"]
        # Le keyword "vélo" matche l'article Vélo électrique, mais l'axe theme
        # matche aussi GPT-5 (theme=tech). Donc 2 résultats.
        assert len(items) == 2
        velo = next(it for it in items if "Vélo" in it["title"])
        assert "keyword" in velo["matched_on"]


class TestSuggestEndpoints:
    """POST /api/veille/suggest/{angles,sources} (Story 23.3)."""

    async def test_suggest_angles_returns_llm_response(self, auth_user, monkeypatch):
        from app.services.veille.llm import angle_suggester as mod
        from app.services.veille.llm.angle_suggester import AngleSuggestion

        fake = AngleSuggestion(
            title="Nouvelles expositions",
            keywords=["expo", "vernissage"],
            reason="Cible les annonces.",
        )

        async def _fake_suggest(self, theme_id, theme_label, brief=""):
            return [fake]

        monkeypatch.setattr(mod.AngleSuggester, "suggest_angles", _fake_suggest)
        # Reset le singleton pour qu'il prenne le monkeypatch
        monkeypatch.setattr(mod, "_angle_suggester", None)

        async with _client() as c:
            r = await c.post(
                "/api/veille/suggest/angles",
                json={
                    "theme_id": "other",
                    "theme_label": "Musées Barcelone",
                    "brief": "Sorties expos",
                },
            )
        assert r.status_code == 200, r.text
        data = r.json()
        assert len(data["angles"]) == 1
        assert data["angles"][0]["title"] == "Nouvelles expositions"
        assert data["angles"][0]["keywords"] == ["expo", "vernissage"]

    async def test_suggest_angles_validates_input(self, auth_user):
        async with _client() as c:
            r = await c.post(
                "/api/veille/suggest/angles",
                json={"theme_id": "", "theme_label": "x"},
            )
        assert r.status_code == 422

    async def test_suggest_sources_returns_llm_response(self, auth_user, monkeypatch):
        from app.services.veille.llm import source_suggester as mod
        from app.services.veille.llm.source_suggester import SourceSuggestion

        fake = SourceSuggestion(
            name="MACBA",
            url="https://www.macba.cat",
            why="Musée officiel.",
            relevance_score=1.0,
        )

        async def _fake_suggest(self, **kwargs):
            return [fake]

        monkeypatch.setattr(mod.SourceSuggester, "suggest_sources", _fake_suggest)
        monkeypatch.setattr(mod, "_source_suggester", None)

        async with _client() as c:
            r = await c.post(
                "/api/veille/suggest/sources",
                json={
                    "theme_id": "other",
                    "theme_label": "Musées Barcelone",
                    "brief": "Sorties expos",
                    "angles": ["Expositions temporaires"],
                    "keywords": ["expo", "macba"],
                },
            )
        assert r.status_code == 200, r.text
        data = r.json()
        assert len(data["sources"]) == 1
        assert data["sources"][0]["name"] == "MACBA"
        assert data["sources"][0]["relevance_score"] == 1.0

    async def test_suggest_sources_empty_response_ok(self, auth_user, monkeypatch):
        from app.services.veille.llm import source_suggester as mod

        async def _fake_empty(self, **kwargs):
            return []

        monkeypatch.setattr(mod.SourceSuggester, "suggest_sources", _fake_empty)
        monkeypatch.setattr(mod, "_source_suggester", None)

        async with _client() as c:
            r = await c.post(
                "/api/veille/suggest/sources",
                json={
                    "theme_id": "other",
                    "theme_label": "Niche super pointue",
                    "brief": "",
                    "angles": [],
                    "keywords": [],
                },
            )
        assert r.status_code == 200
        assert r.json() == {"sources": []}


class TestOtherThemeIngestion:
    """theme_id='other' (tuile Autre) doit mapper vers theme='custom' à l'ingestion."""

    async def test_other_theme_niche_source_ingestion(
        self, auth_user, monkeypatch
    ):
        from unittest.mock import AsyncMock
        from app.services import source_service

        async def _fake_detect(self, url):
            from types import SimpleNamespace

            return SimpleNamespace(
                name="MACBA",
                feed_url=f"{url}/feed.xml",
                detected_type="article",
                description="Musée",
                logo_url=None,
            )

        monkeypatch.setattr(source_service.SourceService, "detect_source", _fake_detect)

        payload = {
            "theme_id": "other",
            "theme_label": "Musées Barcelone",
            "topics": [],
            "source_selections": [
                {
                    "kind": "niche",
                    "niche_candidate": {
                        "name": "MACBA",
                        "url": "https://www.macba.cat",
                        "why": None,
                    },
                }
            ],
            "keywords": [],
        }
        async with _client() as c:
            r = await c.post("/api/veille/config", json=payload)
        assert r.status_code == 200, r.text
        data = r.json()
        assert data["theme_id"] == "other"
        # La source ingérée doit avoir theme='custom' (mappé depuis 'other')
        assert data["sources"][0]["source"]["theme"] == "custom"


class TestLegacyGoneShims:
    async def test_suggestions_topics_410(self, auth_user):
        async with _client() as c:
            r = await c.post("/api/veille/suggestions/topics", json={})
        assert r.status_code == 410

    async def test_suggestions_sources_410(self, auth_user):
        async with _client() as c:
            r = await c.post("/api/veille/suggestions/sources", json={})
        assert r.status_code == 410

    async def test_deliveries_list_410(self, auth_user):
        async with _client() as c:
            r = await c.get("/api/veille/deliveries")
        assert r.status_code == 410

    async def test_deliveries_get_410(self, auth_user):
        async with _client() as c:
            r = await c.get(f"/api/veille/deliveries/{uuid4()}")
        assert r.status_code == 410

    async def test_deliveries_generate_410(self, auth_user):
        async with _client() as c:
            r = await c.post("/api/veille/deliveries/generate", json={})
        assert r.status_code == 410

    async def test_deliveries_generate_first_410(self, auth_user):
        async with _client() as c:
            r = await c.post("/api/veille/deliveries/generate-first")
        assert r.status_code == 410
