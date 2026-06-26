"""Tests d'intégration `GET /api/users/top-themes` — sections « Choisie pour
vous » (Story 22.3).

Vérifie l'orchestration : daily_rank sur les validées, suggérées appended avec
`origin="suggested"` + `reason` + `daily_rank`, gating via la préférence
`tournee_smart_arrangement`, et rétro-compat des défauts.
"""

from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from app.database import get_db
from app.dependencies import get_current_user_id
from app.main import app
from app.models.content import Content
from app.models.enums import (
    ContentType,
    InterestState,
    ReliabilityScore,
    SourceType,
)
from app.models.source import Source, UserSource
from app.models.user import UserInterest, UserPreference, UserProfile
from app.models.user_favorites import UserFavoriteInterest


def _source(name: str, theme: str) -> Source:
    return Source(
        id=uuid4(),
        name=name,
        url=f"https://example.com/{uuid4()}",
        feed_url=f"https://example.com/{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme=theme,
        is_active=True,
        is_curated=True,
        reliability_score=ReliabilityScore.HIGH,
    )


def _content(source_id, theme: str, days_ago: int) -> Content:
    return Content(
        id=uuid4(),
        source_id=source_id,
        title="Article",
        url=f"https://example.com/{uuid4()}",
        guid=str(uuid4()),
        published_at=datetime.now(UTC) - timedelta(days=days_ago),
        content_type=ContentType.ARTICLE,
        theme=theme,
    )


@pytest_asyncio.fixture
async def configured_user(db_session):
    """User avec 1 favori (tech) + thème suivi 'science' alimenté en contenu."""
    user_id = uuid4()
    db_session.add(UserProfile(user_id=user_id, onboarding_completed=True))
    for slug in ("tech", "science"):
        db_session.add(
            UserInterest(
                user_id=user_id,
                interest_slug=slug,
                weight=1.0,
                state=InterestState.FOLLOWED,
            )
        )
    # tech est épinglé (favori) → section validée.
    db_session.add(
        UserFavoriteInterest(user_id=user_id, position=0, interest_slug="tech")
    )
    # science a du contenu récent → candidat suggéré.
    src = _source("Science Source", "science")
    db_session.add(src)
    await db_session.flush()
    for d in range(5):
        db_session.add(_content(src.id, "science", days_ago=d))
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
async def test_appends_suggestion_with_origin_reason_rank(configured_user):
    """La validée (tech) reste origin=validated ; science arrive suggested."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        resp = await ac.get("/api/users/top-themes")
    assert resp.status_code == 200
    body = resp.json()

    validated = [t for t in body if t["origin"] == "validated"]
    suggested = [t for t in body if t["origin"] == "suggested"]
    assert [t["interest_slug"] for t in validated] == ["tech"]
    assert validated[0]["daily_rank"] == 0
    assert validated[0]["reason"] is None  # rétro-compat : pas de reason sur validée

    assert any(t["interest_slug"] == "science" for t in suggested)
    science = next(t for t in suggested if t["interest_slug"] == "science")
    assert science["reason"] is not None
    assert science["reason"]["label"]
    assert len(science["reason"]["breakdown"]) >= 1
    assert science["daily_rank"] == 1  # juste après la validée


@pytest.mark.asyncio
async def test_disabled_via_preference(configured_user, db_session):
    """`tournee_smart_arrangement="false"` → aucune suggérée."""
    db_session.add(
        UserPreference(
            user_id=configured_user,
            preference_key="tournee_smart_arrangement",
            preference_value="false",
        )
    )
    await db_session.commit()

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        resp = await ac.get("/api/users/top-themes")
    body = resp.json()
    assert all(t["origin"] == "validated" for t in body)
    assert [t["interest_slug"] for t in body] == ["tech"]


@pytest.mark.asyncio
async def test_seven_favorites_leaves_one_suggestion_slot(db_session):
    """7 favoris validés → la cible additive (8) laisse 1 slot → 1 suggérée.

    Sous le mécanisme additif (`TOURNEE_TARGET_SECTIONS=8`), un compte à 7
    favoris (plafond `FAVORITE_CAP`) reçoit exactement 1 suggestion, au lieu de
    plafonner à 7 comme avec l'ancien reliquat de plafond favoris.
    """
    user_id = uuid4()
    db_session.add(UserProfile(user_id=user_id, onboarding_completed=True))
    slugs = ["tech", "science", "society", "culture", "economy", "politics", "sport"]
    for pos, slug in enumerate(slugs):
        db_session.add(
            UserFavoriteInterest(user_id=user_id, position=pos, interest_slug=slug)
        )
        db_session.add(
            UserInterest(
                user_id=user_id,
                interest_slug=slug,
                weight=1.0,
                state=InterestState.FOLLOWED,
            )
        )
    # Une source suivie qui comble l'unique slot restant.
    src = _source("Extra", "international")
    db_session.add(src)
    await db_session.flush()
    for d in range(5):
        db_session.add(_content(src.id, "international", days_ago=d))
    db_session.add(
        UserSource(
            user_id=user_id,
            source_id=src.id,
            is_custom=False,
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
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            resp = await ac.get("/api/users/top-themes")
        body = resp.json()
        validated = [t for t in body if t["origin"] == "validated"]
        suggested = [t for t in body if t["origin"] == "suggested"]
        # 7 validés (plafond favoris) + 1 suggéré (cible additive 8).
        assert len(validated) == 7
        assert len(suggested) == 1
        assert len(body) == 8
        # Le slot restant est comblé par la source internationale suivie.
        assert suggested[0]["kind"] == "source"
        assert suggested[0]["source_id"] == str(src.id)
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)
        app.dependency_overrides.pop(get_db, None)


@pytest.mark.asyncio
async def test_source_suggestion_serialization(db_session):
    """Une source suggérée porte kind=source + source_id dans le payload JSON."""
    user_id = uuid4()
    db_session.add(UserProfile(user_id=user_id, onboarding_completed=True))
    db_session.add(
        UserFavoriteInterest(user_id=user_id, position=0, interest_slug="tech")
    )
    src = _source("Mediapart", "politics")
    db_session.add(src)
    await db_session.flush()
    for d in range(6):
        db_session.add(_content(src.id, "politics", days_ago=d))
    db_session.add(
        UserSource(
            user_id=user_id,
            source_id=src.id,
            is_custom=False,
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
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            resp = await ac.get("/api/users/top-themes")
        body = resp.json()
        sources = [t for t in body if t["kind"] == "source"]
        assert len(sources) == 1
        assert sources[0]["source_id"] == str(src.id)
        assert sources[0]["origin"] == "suggested"
        assert sources[0]["reason"] is not None
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)
        app.dependency_overrides.pop(get_db, None)
