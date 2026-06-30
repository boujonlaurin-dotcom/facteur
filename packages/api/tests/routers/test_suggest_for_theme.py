"""Tests de GET /api/sources/suggest-for-theme/{slug} — footer « Étoffer [thème] ».

Couvre : le mapping des tiers (Tier 1 pépite / Tier 2 catalogue évalué), le
garde-fou éditorial (exclusion fiabilité basse/inconnue + biais alternatif des
tiers poussés), l'exclusion des sources déjà suivies, le thème vide et l'auth.
"""

from uuid import uuid4

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from app.database import get_db
from app.dependencies import get_current_user_id
from app.main import app
from app.models.enums import BiasStance, InterestState, ReliabilityScore, SourceType
from app.models.source import Source, UserSource


def _make_source(
    name: str,
    *,
    theme: str = "tech",
    is_curated: bool = True,
    is_pepite: bool = False,
    pepite_themes: list[str] | None = None,
    bias: BiasStance = BiasStance.CENTER,
    reliability: ReliabilityScore = ReliabilityScore.HIGH,
    recommended_by: str | None = None,
    recommendation_reason: str | None = None,
    secondary_themes: list[str] | None = None,
) -> Source:
    slug = name.lower().replace(" ", "").replace(".", "")
    return Source(
        id=uuid4(),
        name=name,
        url=f"https://{slug}.example.com",
        feed_url=f"https://{slug}.example.com/feed-{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme=theme,
        is_active=True,
        is_curated=is_curated,
        is_pepite_recommendation=is_pepite,
        pepite_for_themes=pepite_themes,
        bias_stance=bias,
        reliability_score=reliability,
        recommended_by=recommended_by,
        recommendation_reason=recommendation_reason,
        secondary_themes=secondary_themes,
    )


@pytest_asyncio.fixture
async def auth_ctx(db_session):
    """Client authentifié + l'UUID du user (pour créer des UserSource)."""
    user_id = uuid4()

    async def _fake_user():
        return str(user_id)

    async def _fake_db():
        yield db_session

    app.dependency_overrides[get_current_user_id] = _fake_user
    app.dependency_overrides[get_db] = _fake_db
    transport = ASGITransport(app=app)
    try:
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            yield ac, user_id
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)
        app.dependency_overrides.pop(get_db, None)


@pytest.mark.asyncio
async def test_tier_mapping_pepite_then_catalog(auth_ctx, db_session):
    client, _ = auth_ctx
    pepite = _make_source(
        "Heidi News",
        theme="science",
        is_pepite=True,
        pepite_themes=["tech"],
        recommended_by="Laurin",
        recommendation_reason="Le meilleur sur la tech.",
    )
    catalog = _make_source("Le Monde", theme="tech")
    db_session.add_all([pepite, catalog])
    await db_session.commit()

    resp = await client.get("/api/sources/suggest-for-theme/tech")
    assert resp.status_code == 200
    body = resp.json()
    assert body["theme"] == "tech"
    assert body["label"] == "Tech"

    by_id = {s["source"]["id"]: s for s in body["suggestions"]}
    assert by_id[str(pepite.id)]["recommendation_tier"] == "facteur_pick"
    assert by_id[str(catalog.id)]["recommendation_tier"] == "quality_catalog"
    # Le Tier 1 (pépite) passe avant le Tier 2.
    assert body["suggestions"][0]["source"]["id"] == str(pepite.id)


@pytest.mark.asyncio
async def test_gate_excludes_low_unknown_alternative(auth_ctx, db_session):
    """Aucune source à fiabilité basse/inconnue ou biais alternatif n'est poussée."""
    client, _ = auth_ctx
    low = _make_source("Low Rel", reliability=ReliabilityScore.LOW)
    unknown = _make_source("Unknown Rel", reliability=ReliabilityScore.UNKNOWN)
    alternative = _make_source(
        "Alt Bias", bias=BiasStance.ALTERNATIVE, reliability=ReliabilityScore.HIGH
    )
    # Une pépite à fiabilité basse ne doit pas non plus apparaître en Tier 1.
    bad_pepite = _make_source(
        "Bad Pepite",
        theme="science",
        is_pepite=True,
        pepite_themes=["tech"],
        reliability=ReliabilityScore.LOW,
    )
    db_session.add_all([low, unknown, alternative, bad_pepite])
    await db_session.commit()

    resp = await client.get("/api/sources/suggest-for-theme/tech")
    assert resp.status_code == 200
    assert resp.json()["suggestions"] == []


@pytest.mark.asyncio
async def test_excludes_followed_sources(auth_ctx, db_session):
    client, user_id = auth_ctx
    followed = _make_source("Suivie", theme="tech")
    fresh = _make_source("Nouvelle", theme="tech")
    db_session.add_all([followed, fresh])
    await db_session.flush()
    db_session.add(
        UserSource(
            user_id=user_id,
            source_id=followed.id,
            state=InterestState.FOLLOWED,
        )
    )
    await db_session.commit()

    resp = await client.get("/api/sources/suggest-for-theme/tech")
    assert resp.status_code == 200
    ids = {s["source"]["id"] for s in resp.json()["suggestions"]}
    assert str(followed.id) not in ids
    assert str(fresh.id) in ids


@pytest.mark.asyncio
async def test_empty_theme_returns_no_suggestions(auth_ctx, db_session):
    client, _ = auth_ctx
    # Une source sur un autre thème ne doit pas remonter.
    db_session.add(_make_source("Hors sujet", theme="culture"))
    await db_session.commit()

    resp = await client.get("/api/sources/suggest-for-theme/tech")
    assert resp.status_code == 200
    body = resp.json()
    assert body["suggestions"] == []
    assert body["label"] == "Tech"


@pytest.mark.asyncio
async def test_secondary_theme_source_is_eligible(auth_ctx, db_session):
    """Une source dont le thème *secondaire* couvre le slug est éligible (Tier 2)."""
    client, _ = auth_ctx
    src = _make_source("Secondaire", theme="economy", secondary_themes=["tech"])
    db_session.add(src)
    await db_session.commit()

    resp = await client.get("/api/sources/suggest-for-theme/tech")
    assert resp.status_code == 200
    ids = {s["source"]["id"] for s in resp.json()["suggestions"]}
    assert str(src.id) in ids


@pytest.mark.asyncio
async def test_requires_auth():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        resp = await ac.get("/api/sources/suggest-for-theme/tech")
    assert resp.status_code in (401, 403)
