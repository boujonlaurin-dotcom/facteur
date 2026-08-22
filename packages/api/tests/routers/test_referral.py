"""Tests des endpoints de parrainage (Story partage.2).

Couvre : création paresseuse du code (alphabet, longueur, stabilité, unicité),
`joined_count`, et l'attribution (nominale, idempotente, auto-parrainage, code
inconnu) qui doit **toujours** répondre 200.
"""

from unittest.mock import MagicMock, patch
from uuid import uuid4

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import func, select

from app.database import get_db
from app.dependencies import get_current_user_id
from app.main import app
from app.models.referral import (
    REFERRAL_CODE_ALPHABET,
    REFERRAL_CODE_LENGTH,
    ReferralAttribution,
    ReferralCode,
)
from app.models.user import UserPreference, UserProfile


@pytest_asyncio.fixture
async def auth_user(db_session):
    """Utilisateur authentifié + overrides FastAPI (db et identité)."""
    user_id = uuid4()
    db_session.add(UserProfile(user_id=user_id, onboarding_completed=True))
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
async def referrer(db_session):
    """Un parrain déjà porteur d'un code, distinct de l'utilisateur courant."""
    user_id = uuid4()
    db_session.add(UserProfile(user_id=user_id, onboarding_completed=True))
    # Deux commits : les FK ciblent `user_profiles`, or SQLAlchemy n'ordonne pas
    # les INSERT entre modèles sans relation déclarée.
    await db_session.commit()
    db_session.add(ReferralCode(user_id=user_id, code="ABC234"))
    await db_session.commit()
    return user_id


def _client() -> AsyncClient:
    return AsyncClient(transport=ASGITransport(app=app), base_url="http://test")


@pytest.fixture
def posthog_mock():
    with patch("app.routers.referral.get_posthog_client") as factory:
        client = MagicMock()
        factory.return_value = client
        yield client


@pytest.mark.asyncio
async def test_me_creates_code_lazily(auth_user, db_session):
    async with _client() as ac:
        resp = await ac.get("/api/referral/me")

    assert resp.status_code == 200
    code = resp.json()["code"]
    assert len(code) == REFERRAL_CODE_LENGTH
    assert set(code) <= set(REFERRAL_CODE_ALPHABET)
    assert resp.json()["joined_count"] == 0

    stored = await db_session.scalar(
        select(ReferralCode.code).where(ReferralCode.user_id == auth_user)
    )
    assert stored == code


@pytest.mark.asyncio
async def test_me_is_stable_across_calls(auth_user, db_session):
    async with _client() as ac:
        first = await ac.get("/api/referral/me")
        second = await ac.get("/api/referral/me")

    assert first.json()["code"] == second.json()["code"]
    rows = await db_session.scalar(
        select(func.count())
        .select_from(ReferralCode)
        .where(ReferralCode.user_id == auth_user)
    )
    assert rows == 1


@pytest.mark.asyncio
async def test_me_counts_attributed_users(auth_user, db_session):
    async with _client() as ac:
        code = (await ac.get("/api/referral/me")).json()["code"]

        filleuls = [uuid4(), uuid4()]
        other = uuid4()  # filleul d'un autre parrain : ne doit pas être compté
        for user_id in (*filleuls, other):
            db_session.add(UserProfile(user_id=user_id))
        await db_session.commit()

        for user_id in filleuls:
            db_session.add(ReferralAttribution(referred_user_id=user_id, code=code))
        db_session.add(ReferralAttribution(referred_user_id=other, code="ZZZ999"))
        await db_session.commit()

        resp = await ac.get("/api/referral/me")

    assert resp.json()["joined_count"] == 2


@pytest.mark.asyncio
async def test_attribution_nominal(auth_user, referrer, db_session, posthog_mock):
    async with _client() as ac:
        resp = await ac.post(
            "/api/referral/attribution",
            json={
                "code": "abc234",  # normalisé en majuscules côté serveur
                "surface": "grille",
                "platform": "android",
                "store": "play",
                "referrer_raw": "utm_source=app&ref=ABC234",
                "utm_source": "app",
                "utm_medium": "partage_in_app",
            },
        )

    assert resp.status_code == 200
    assert resp.json() == {"attributed": True}

    row = await db_session.scalar(
        select(ReferralAttribution).where(
            ReferralAttribution.referred_user_id == auth_user
        )
    )
    assert row is not None
    assert row.code == "ABC234"
    assert row.surface == "grille"
    assert row.utm_source == "app"
    assert row.utm_medium == "partage_in_app"

    source = await db_session.scalar(
        select(UserPreference.preference_value).where(
            UserPreference.user_id == auth_user,
            UserPreference.preference_key == "acquisition_source",
        )
    )
    assert source == "referral"

    posthog_mock.capture.assert_called_once()
    assert posthog_mock.capture.call_args.args[1] == "referral_attributed"
    # Cohortes d'acquisition PostHog : même propagation que le tag admin.
    posthog_mock.identify.assert_called_once()


@pytest.mark.asyncio
async def test_attribution_is_idempotent(auth_user, referrer, db_session, posthog_mock):
    async with _client() as ac:
        first = await ac.post("/api/referral/attribution", json={"code": "ABC234"})
        second = await ac.post("/api/referral/attribution", json={"code": "ABC234"})

    assert first.json() == {"attributed": True}
    assert second.status_code == 200
    assert second.json() == {"attributed": False}

    rows = await db_session.scalar(
        select(func.count())
        .select_from(ReferralAttribution)
        .where(ReferralAttribution.referred_user_id == auth_user)
    )
    assert rows == 1


@pytest.mark.asyncio
async def test_attribution_rejects_self_referral(auth_user, db_session, posthog_mock):
    db_session.add(ReferralCode(user_id=auth_user, code="SELF99"))
    await db_session.commit()

    async with _client() as ac:
        resp = await ac.post("/api/referral/attribution", json={"code": "SELF99"})

    assert resp.status_code == 200
    assert resp.json() == {"attributed": False}
    rows = await db_session.scalar(
        select(func.count()).select_from(ReferralAttribution)
    )
    assert rows == 0
    posthog_mock.capture.assert_not_called()


@pytest.mark.asyncio
async def test_attribution_unknown_code(auth_user, db_session, posthog_mock):
    async with _client() as ac:
        resp = await ac.post("/api/referral/attribution", json={"code": "NOPE42"})

    assert resp.status_code == 200
    assert resp.json() == {"attributed": False}
    rows = await db_session.scalar(
        select(func.count()).select_from(ReferralAttribution)
    )
    assert rows == 0


@pytest.mark.asyncio
async def test_attribution_empty_code_is_a_noop(auth_user, posthog_mock):
    async with _client() as ac:
        resp = await ac.post("/api/referral/attribution", json={"code": "  "})

    assert resp.status_code == 200
    assert resp.json() == {"attributed": False}


@pytest.mark.asyncio
async def test_attribution_truncates_oversized_fields(
    auth_user, referrer, db_session, posthog_mock
):
    """Les valeurs trop longues sont tronquées, jamais rejetées (toujours 200)."""
    async with _client() as ac:
        resp = await ac.post(
            "/api/referral/attribution",
            json={
                "code": "ABC234",
                "surface": "s" * 120,
                "platform": "p" * 40,
                "referrer_raw": "r" * 5000,
            },
        )

    assert resp.json() == {"attributed": True}
    row = await db_session.scalar(
        select(ReferralAttribution).where(
            ReferralAttribution.referred_user_id == auth_user
        )
    )
    assert len(row.surface) == 40
    assert len(row.platform) == 16
    assert len(row.referrer_raw) == 2000  # String(2000) du modèle


@pytest.mark.asyncio
async def test_attribution_creates_the_profile_of_a_fresh_install(
    db_session, referrer, posthog_mock
):
    """Premier lancement : aucun `user_profiles` encore, les FK doivent tenir."""
    user_id = uuid4()

    async def _fake_user():
        return str(user_id)

    async def _fake_db():
        yield db_session

    app.dependency_overrides[get_current_user_id] = _fake_user
    app.dependency_overrides[get_db] = _fake_db
    try:
        async with _client() as ac:
            attribution = await ac.post(
                "/api/referral/attribution", json={"code": "ABC234"}
            )
            me = await ac.get("/api/referral/me")
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)
        app.dependency_overrides.pop(get_db, None)

    assert attribution.json() == {"attributed": True}
    assert me.status_code == 200
    assert len(me.json()["code"]) == REFERRAL_CODE_LENGTH


@pytest.mark.asyncio
async def test_attribution_keeps_a_more_specific_acquisition_source(
    auth_user, referrer, db_session, posthog_mock
):
    """Une source déjà posée (waitlist, creator…) n'est pas écrasée."""
    db_session.add(
        UserPreference(
            user_id=auth_user,
            preference_key="acquisition_source",
            preference_value="waitlist",
        )
    )
    await db_session.commit()

    async with _client() as ac:
        resp = await ac.post("/api/referral/attribution", json={"code": "ABC234"})

    assert resp.json() == {"attributed": True}
    source = await db_session.scalar(
        select(UserPreference.preference_value).where(
            UserPreference.user_id == auth_user,
            UserPreference.preference_key == "acquisition_source",
        )
    )
    assert source == "waitlist"
    posthog_mock.identify.assert_not_called()
