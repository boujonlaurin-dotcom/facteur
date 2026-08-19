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
async def test_seven_favorites_still_gets_floor_suggestions(db_session):
    """7 favoris validés → plancher garanti `FLOOR` (4) suggestions (Story 22.6).

    L'ancien reliquat de cible plafonnait un compte chargé à 1 suggestion
    (« plus tu configures, moins tu vois »). Le plancher 22.6 vise
    `min(SUBCAP, max(remaining, FLOOR))` : un pool de 5 sources suivies non
    épinglées sert donc 4 suggestions, pas 1.

    Story 22.8 (cible 10) — `remaining` passe de 1 à 3, mais reste sous `FLOOR`
    (4) : le résultat est **inchangé** à 4 suggestions. C'est la démonstration
    que le bump de cible ne touche pas les comptes chargés.
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
    # 5 sources suivies non épinglées → pool de suggestions au-dessus du plancher.
    src_themes = ["international", "environment", "health", "media", "justice"]
    for name in src_themes:
        src = _source(f"Src {name}", name)
        db_session.add(src)
        await db_session.flush()
        for d in range(3):
            db_session.add(_content(src.id, name, days_ago=d))
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
        # 7 validés (plafond favoris) + plancher 4 suggérées (pas 1).
        assert len(validated) == 7
        assert len(suggested) == 4
        assert len(body) == 11
        assert all(t["kind"] == "source" for t in suggested)
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)
        app.dependency_overrides.pop(get_db, None)


@pytest.mark.asyncio
async def test_five_favorites_reaches_target_of_ten_sections(db_session):
    """5 favoris + pool riche → 10 sections thématiques (Story 22.8).

    C'est le cas que le bump de cible 8 → 10 change réellement :
    - avant : `min(SUBCAP=5, max(remaining=3, FLOOR=4)) = 4` → 9 sections ;
    - après : `min(SUBCAP=5, max(remaining=5, FLOOR=4)) = 5` → 10 sections.

    Verrouille le fait que la cible n'est atteinte que lorsque `remaining` repasse
    au-dessus de `FLOOR` sans dépasser `SUBCAP` (favoris 4 et 5 uniquement).
    """
    user_id = uuid4()
    db_session.add(UserProfile(user_id=user_id, onboarding_completed=True))
    slugs = ["tech", "science", "society", "culture", "economy"]
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
    # 6 sources suivies alimentées → pool strictement au-dessus de SUBCAP, pour
    # que le nombre servi soit bien borné par le calcul et non par la disette.
    for name in ["international", "environment", "health", "media", "justice", "tech2"]:
        src = _source(f"Src {name}", name)
        db_session.add(src)
        await db_session.flush()
        for d in range(3):
            db_session.add(_content(src.id, name, days_ago=d))
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
        assert len(validated) == 5
        assert len(suggested) == 5
        assert len(body) == 10
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)
        app.dependency_overrides.pop(get_db, None)


@pytest.mark.asyncio
async def test_suggestions_never_exceed_subcap(db_session):
    """Pool riche + 0 favori → au plus `SUBCAP` (5) suggestions (Story 22.6).

    0 favori valide → `min(SUBCAP=5, max(remaining=10, FLOOR=4)) = 5` : un pool
    de 8 sources suivies est plafonné à 5, jamais 8.

    Story 22.8 — c'est ce plafond qui rend le bump de cible (8 → 10) inerte pour
    les comptes peu configurés : `SUBCAP` écrase `remaining`, donc un compte à 0
    favori reste à 5 sections. La cible est alimentée par `FAVORITE_CAP`, pas
    par les suggestions.
    """
    user_id = uuid4()
    db_session.add(UserProfile(user_id=user_id, onboarding_completed=True))
    # Un thème suivi SANS contenu récent : garde le fallback hors early-return
    # `[]` mais reste hors des validées (aucun article 14j) et hors du pool
    # suggéré (plancher contenu).
    db_session.add(
        UserInterest(
            user_id=user_id,
            interest_slug="tech",
            weight=1.0,
            state=InterestState.FOLLOWED,
        )
    )
    # 8 sources suivies alimentées → pool > SUBCAP.
    names = ["a", "b", "c", "d", "e", "f", "g", "h"]
    for name in names:
        src = _source(f"Src {name}", name)
        db_session.add(src)
        await db_session.flush()
        for d in range(3):
            db_session.add(_content(src.id, name, days_ago=d))
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
        assert len(validated) == 0
        assert len(suggested) == 5  # plafonné à SUBCAP, pas 8
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
