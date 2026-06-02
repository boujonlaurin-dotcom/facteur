"""Tests pour le router /api/veille (Story 23.1).

Couvre les endpoints refondus en filtre temps-réel :
- GET / POST / DELETE /config (avec keywords[])
- GET /feed (matching OR thèmes/topics/sources/keywords + boost source)
- 410 Gone shim sur /suggestions/* et /deliveries/* (clients legacy)
"""

from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

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

    async def test_post_config_persists_angle_keyword_clusters(
        self, auth_user, curated_tech_source, db_session
    ):
        """Story curation : un angle `suggested` + sa grappe → VeilleKeyword liés."""
        from app.models.veille import VeilleKeyword

        payload = {
            "theme_id": "tech",
            "theme_label": "Tech",
            "topics": [
                {
                    "topic_id": "ia-generative",
                    "label": "IA générative",
                    "kind": "suggested",
                    "keywords": ["GPT-5", "Mistral", "gpt-5"],  # dédup attendu
                }
            ],
            "keywords": [{"keyword": "souveraineté", "position": 0}],
        }
        async with _client() as c:
            r = await c.post("/api/veille/config", json=payload)
        assert r.status_code == 200, r.text
        data = r.json()
        # Round-trip : la grappe niche sous l'angle, le mot-clé global reste à plat.
        assert len(data["topics"]) == 1
        assert data["topics"][0]["keywords"] == ["gpt-5", "mistral"]
        assert [k["keyword"] for k in data["keywords"]] == ["souveraineté"]

        # En base : 2 keywords liés à l'angle + 1 global (veille_topic_id NULL).
        rows = (
            (
                await db_session.execute(
                    select(VeilleKeyword).where(
                        VeilleKeyword.veille_config_id == UUID(data["id"])
                    )
                )
            )
            .scalars()
            .all()
        )
        linked = [r for r in rows if r.veille_topic_id is not None]
        globals_ = [r for r in rows if r.veille_topic_id is None]
        assert len(linked) == 2
        assert len(globals_) == 1
        assert globals_[0].keyword == "souveraineté"

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

    async def test_get_config_self_heals_missing_favorite(
        self, auth_user, db_session
    ):
        """Story 23.4 : une config active orpheline (sans favori — cas proton) est
        réparée au `GET /config` (self-heal idempotent, commit dédié)."""
        cfg = VeilleConfig(
            id=uuid4(),
            user_id=auth_user,
            theme_id="tech",
            theme_label="Tech",
            status=VeilleStatus.ACTIVE.value,
        )
        db_session.add(cfg)
        await db_session.commit()

        # Orphelin : config active, aucun VeilleFavoriteRef.
        assert await self._favorites(db_session, auth_user) == []

        async with _client() as c:
            r = await c.get("/api/veille/config")
        assert r.status_code == 200

        favs = await self._favorites(db_session, auth_user)
        assert len(favs) == 1
        assert favs[0].veille_config_id == cfg.id
        assert favs[0].interest_slug is None


class TestFeed:
    async def test_feed_empty_when_no_config(self, auth_user):
        async with _client() as c:
            r = await c.get("/api/veille/feed")
        assert r.status_code == 200
        assert r.json()["items"] == []

    async def test_feed_source_axis_returns_all_but_theme_not_qualifying(
        self, auth_user, curated_tech_source, tech_content
    ):
        """La source est un axe fort → ses 3 articles entrent dans le pool.

        Contrat inversé : le thème n'est plus un axe **qualifiant** —
        `matched_on` n'expose plus "theme" même quand content.theme == config.theme.
        """
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
        assert len(data["items"]) == 3
        gpt = next(it for it in data["items"] if "GPT-5" in it["title"])
        assert "source" in gpt["matched_on"]
        assert "theme" not in gpt["matched_on"]

    async def test_feed_theme_only_article_excluded(
        self, auth_user, curated_tech_source, tech_content
    ):
        """Config sur un topic précis → un article « thème macro seul » est exclu.

        Le thème étant retiré du prédicat, GPT-5 (topics=["ai","openai"]) entre
        via le topic "ai" mais l'article Bourse (theme=economy, hors topic, hors
        source suivie, hors keyword) n'entre jamais dans le pool.
        """
        payload = {
            "theme_id": "tech",
            "theme_label": "Tech",
            "topics": [{"topic_id": "ai", "label": "IA", "kind": "preset"}],
        }
        async with _client() as c:
            await c.post("/api/veille/config", json=payload)
            r = await c.get("/api/veille/feed?limit=20")
        items = r.json()["items"]
        titles = [it["title"] for it in items]
        assert any("GPT-5" in t for t in titles)
        assert not any("Bourse" in t for t in titles)
        assert not any("Vélo" in t for t in titles)

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
        # Seul l'article "Vélo électrique" matche le keyword. GPT-5 n'entre plus
        # via le thème (retiré du prédicat) → 1 seul résultat (contrat inversé).
        assert len(items) == 1
        velo = items[0]
        assert "Vélo" in velo["title"]
        assert "keyword" in velo["matched_on"]


class TestSuggestEndpoints:
    """POST /api/veille/suggest/{angles,sources} (Story 23.3)."""

    async def test_resolve_topic_enriches_without_creating_profile(
        self, auth_user, monkeypatch, db_session
    ):
        from app.models.user_topic_profile import UserTopicProfile
        from app.services.ml import topic_enrichment_service as mod
        from app.services.ml.topic_enrichment_service import TopicEnrichmentResult

        async def _fake_enrich(self, topic_name):
            return TopicEnrichmentResult(
                slug_parent="culture",
                keywords=["macba", "exposition", "art contemporain"],
                intent_description="Suivi des expositions à Barcelone",
                entity_type="LOCATION",
                canonical_name="Musées contemporains de Barcelone",
            )

        monkeypatch.setattr(mod.TopicEnrichmentService, "enrich", _fake_enrich)
        monkeypatch.setattr(mod, "_topic_enrichment_service", None)

        async with _client() as c:
            r = await c.post(
                "/api/veille/resolve/topic",
                json={
                    "topic": "musées barcelone",
                    "theme_id": "culture",
                    "theme_label": "Culture",
                },
            )

        assert r.status_code == 200, r.text
        data = r.json()
        assert data["label"] == "Musées contemporains de Barcelone"
        assert data["topic_id"] == "custom-musees-contemporains-de-barcelone"
        assert data["keywords"] == ["macba", "exposition", "art contemporain"]
        assert data["description"] == "Suivi des expositions à Barcelone"
        assert data["metadata"]["slug_parent"] == "culture"

        rows = (
            (
                await db_session.execute(
                    select(UserTopicProfile).where(
                        UserTopicProfile.user_id == auth_user
                    )
                )
            )
            .scalars()
            .all()
        )
        assert rows == []

    async def test_resolve_topic_validates_input(self, auth_user):
        async with _client() as c:
            r = await c.post("/api/veille/resolve/topic", json={"topic": ""})
        assert r.status_code == 422

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

    async def test_suggest_sources_truncates_overflow_instead_of_422(
        self, auth_user, monkeypatch
    ):
        from app.services.veille.llm import source_suggester as mod

        captured = {}

        async def _fake_empty(self, **kwargs):
            captured.update(kwargs)
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
                    "angles": [f"angle-{i}" for i in range(30)],
                    "keywords": [f"kw-{i}" for i in range(60)],
                },
            )
        assert r.status_code == 200, r.text
        assert r.json() == {"sources": []}
        assert len(captured["angles"]) == 20
        assert len(captured["keywords"]) == 40
        assert captured["angles"] == [f"angle-{i}" for i in range(20)]
        assert captured["keywords"] == [f"kw-{i}" for i in range(40)]


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
