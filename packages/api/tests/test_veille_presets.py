"""Tests pour GET /api/veille/presets + module de données.

Couvre :
- Le module statique `veille_presets.py` charge sans crash et expose 3
  pré-sets avec la structure attendue (verrouille les slugs cibles V1).
- L'endpoint hydrate les sources curées depuis la table `sources`
  (filtre `theme + is_curated`) sans contrat sur le nombre exact (le seed
  prod garantit ≥4 mais les tests posent leurs propres fixtures).
"""

from uuid import uuid4

import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from app.data.veille_presets import VEILLE_PRESETS, get_presets
from app.database import get_db
from app.main import app
from app.models.enums import SourceType
from app.models.source import Source

EXPECTED_SLUGS = ["ia_agentique", "geopolitique_long", "transition_climat"]
EXPECTED_THEMES = {
    "ia_agentique": "tech",
    "geopolitique_long": "international",
    "transition_climat": "environment",
}


def _client():
    transport = ASGITransport(app=app)
    return AsyncClient(transport=transport, base_url="http://test")


@pytest_asyncio.fixture
async def db_override(db_session):
    async def _fake_db():
        yield db_session

    app.dependency_overrides[get_db] = _fake_db
    try:
        yield db_session
    finally:
        app.dependency_overrides.pop(get_db, None)


@pytest_asyncio.fixture
async def curated_sources_per_theme(db_session):
    """Pose 4 sources curées (active) par thème ciblé par les pré-sets."""
    created: list[Source] = []
    for theme in EXPECTED_THEMES.values():
        for i in range(4):
            src = Source(
                id=uuid4(),
                name=f"Source {theme} {i}",
                url=f"https://{theme}{i}.example.com",
                feed_url=f"https://{theme}{i}.example.com/feed-{uuid4()}.xml",
                type=SourceType.ARTICLE,
                theme=theme,
                is_active=True,
                is_curated=True,
            )
            db_session.add(src)
            created.append(src)
    await db_session.commit()
    return created


def test_get_presets_module_loads():
    """Sanity check : le module charge et expose la structure attendue."""
    presets = get_presets()
    assert presets is VEILLE_PRESETS
    assert len(presets) == 3
    assert [p["slug"] for p in presets] == EXPECTED_SLUGS

    required_keys = {
        "slug",
        "label",
        "accroche",
        "theme_id",
        "theme_label",
        "topics",
        "purposes",
        "editorial_brief",
    }
    for p in presets:
        assert required_keys.issubset(p.keys())
        assert p["theme_id"] == EXPECTED_THEMES[p["slug"]]
        assert isinstance(p["topics"], list) and len(p["topics"]) >= 1
        assert isinstance(p["purposes"], list)


async def test_list_presets_returns_three_items(db_override, curated_sources_per_theme):
    async with _client() as ac:
        resp = await ac.get("/api/veille/presets")
    assert resp.status_code == 200
    data = resp.json()
    assert isinstance(data, list)
    assert len(data) == 3
    assert [p["slug"] for p in data] == EXPECTED_SLUGS


async def test_presets_hydrate_curated_sources(db_override, curated_sources_per_theme):
    async with _client() as ac:
        resp = await ac.get("/api/veille/presets")
    assert resp.status_code == 200
    data = resp.json()

    for preset in data:
        sources = preset["sources"]
        assert len(sources) >= 4, (
            f"preset {preset['slug']} doit hydrater ≥4 sources curées"
        )
        for src in sources:
            assert src["theme"] == preset["theme_id"]
            assert src["is_curated"] is True
            assert "name" in src and "url" in src
