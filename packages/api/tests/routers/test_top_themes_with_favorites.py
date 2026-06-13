"""Test extension `GET /api/users/top-themes` (Story 22.1).

Vérifie que la table `user_favorite_interests` prime sur le fallback
weight-desc, et que la rétrocompat `List[TopThemeResponse]` est préservée.
"""

from uuid import uuid4

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from app.database import get_db
from app.dependencies import get_current_user_id
from app.main import app
from app.models.enums import InterestState
from app.models.user import UserInterest, UserProfile
from app.models.user_favorites import UserFavoriteInterest
from app.models.veille import VeilleConfig, VeilleStatus


@pytest_asyncio.fixture
async def user_with_4_interests(db_session):
    user_id = uuid4()
    db_session.add(UserProfile(user_id=user_id, onboarding_completed=True))
    weights = {"tech": 1.5, "society": 0.7, "culture": 1.2, "science": 0.9}
    for slug, w in weights.items():
        db_session.add(
            UserInterest(
                user_id=user_id,
                interest_slug=slug,
                weight=w,
                state=InterestState.FOLLOWED,
            )
        )
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


@pytest.mark.asyncio
async def test_returns_favorites_in_position_order_when_present(
    user_with_4_interests, db_session
):
    """Quand des favoris existent, ils priment sur le tri par weight."""
    user_id = user_with_4_interests
    # User a déclaré ses favoris dans un ordre custom (≠ weight desc).
    db_session.add(
        UserFavoriteInterest(
            user_id=user_id, position=0, interest_slug="society"
        )
    )
    db_session.add(
        UserFavoriteInterest(
            user_id=user_id, position=1, interest_slug="science"
        )
    )
    await db_session.commit()

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        resp = await ac.get("/api/users/top-themes")
    assert resp.status_code == 200
    slugs = [t["interest_slug"] for t in resp.json()]
    # Ordre = position 0,1 → society, science (PAS tech qui aurait gagné en weight).
    assert slugs == ["society", "science"]


@pytest.mark.asyncio
async def test_falls_back_to_weight_when_no_favorites(
    user_with_4_interests, db_session
):
    """Sans favoris déclarés, retombe sur le tri weight desc + filtre articles
    14j (qui exclut tout dans ce test → liste vide attendue)."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        resp = await ac.get("/api/users/top-themes")
    assert resp.status_code == 200
    # Pas d'articles → fallback retourne [] (filtre 14j).
    assert resp.json() == []


@pytest.mark.asyncio
async def test_top_themes_includes_veille_with_kind_discriminator(
    user_with_4_interests, db_session
):
    """Story 23.1 PR-3 : un favori veille est sérialisé avec kind=veille +
    veille_config_id, son slug est le theme_id de la VeilleConfig."""
    user_id = user_with_4_interests
    cfg = VeilleConfig(
        id=uuid4(),
        user_id=user_id,
        theme_id="tech",
        theme_label="Tech",
        status=VeilleStatus.ACTIVE.value,
    )
    db_session.add(cfg)
    await db_session.flush()
    db_session.add(
        UserFavoriteInterest(
            user_id=user_id, position=0, interest_slug="society"
        )
    )
    db_session.add(
        UserFavoriteInterest(user_id=user_id, position=1, veille_config_id=cfg.id)
    )
    await db_session.commit()

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        resp = await ac.get("/api/users/top-themes")
    assert resp.status_code == 200
    body = resp.json()
    assert len(body) == 2
    assert body[0]["interest_slug"] == "society"
    assert body[0]["kind"] == "theme"
    assert body[0]["veille_config_id"] is None
    assert body[1]["interest_slug"] == "tech"
    assert body[1]["kind"] == "veille"
    assert body[1]["veille_config_id"] == str(cfg.id)


@pytest.mark.asyncio
async def test_top_themes_skips_archived_veille_favorite(
    user_with_4_interests, db_session
):
    """Un favori orphelin (cfg archivée hors transaction) est skippé."""
    user_id = user_with_4_interests
    cfg = VeilleConfig(
        id=uuid4(),
        user_id=user_id,
        theme_id="tech",
        theme_label="Tech",
        status=VeilleStatus.ARCHIVED.value,
    )
    db_session.add(cfg)
    await db_session.flush()
    db_session.add(
        UserFavoriteInterest(
            user_id=user_id, position=0, interest_slug="society"
        )
    )
    db_session.add(
        UserFavoriteInterest(user_id=user_id, position=1, veille_config_id=cfg.id)
    )
    await db_session.commit()

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        resp = await ac.get("/api/users/top-themes")
    assert resp.status_code == 200
    body = resp.json()
    assert len(body) == 1
    assert body[0]["interest_slug"] == "society"
    assert body[0]["kind"] == "theme"
