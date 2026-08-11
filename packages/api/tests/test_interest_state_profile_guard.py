"""Garantir `user_profiles` avant toute écriture d'état d'intérêt.

`user_favorite_sources`, `user_favorite_interests` et `user_interests` portent
une FK vers `user_profiles.user_id`. Un compte authentifié sans row de profil
(créé hors du flux d'onboarding) faisait donc échouer le commit en 500 —
`user_favorite_sources_user_id_fkey` (remonté par Sentry en prod). Ces tests
verrouillent la garde `get_or_create_profile` posée en tête des deux `set_state`.
"""

from unittest.mock import MagicMock, patch
from uuid import uuid4

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import func, select

from app.database import get_db
from app.dependencies import get_current_user_id
from app.main import app
from app.models.enums import InterestState, SourceType
from app.models.source import Source
from app.models.user import UserProfile, UserStreak
from app.models.user_favorites import UserFavoriteInterest, UserFavoriteSource
from app.services.user_interests_service import (
    UserInterestsService,
    UserSourcesStateService,
)


async def _make_source(db):
    source = Source(
        id=uuid4(),
        name="Profile Guard Source",
        url="https://guard.example.com",
        feed_url=f"https://guard.example.com/feed-{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="society",
        is_active=True,
        is_curated=False,
    )
    db.add(source)
    await db.commit()
    return source


async def _count(db, model, user_id):
    return (
        await db.execute(
            select(func.count()).select_from(model).where(model.user_id == user_id)
        )
    ).scalar_one()


@pytest.mark.asyncio
async def test_favorite_source_without_profile_creates_it(db_session):
    """FAVORITE sur un user sans `user_profiles` : 200 au lieu du 500 FK."""
    user_id = uuid4()
    source = await _make_source(db_session)
    service = UserSourcesStateService(db_session)

    await service.set_state(user_id, source.id, InterestState.FAVORITE)

    assert await _count(db_session, UserProfile, user_id) == 1
    fav = (
        await db_session.execute(
            select(UserFavoriteSource).where(
                UserFavoriteSource.user_id == user_id,
                UserFavoriteSource.source_id == source.id,
            )
        )
    ).scalar_one()
    assert fav.position == 0


@pytest.mark.asyncio
async def test_favorite_theme_without_profile_creates_it(db_session):
    """Même angle mort côté Thèmes (`user_interests` + favoris thèmes)."""
    user_id = uuid4()
    service = UserInterestsService(db_session)

    await service.set_state(
        user_id=user_id,
        kind="theme",
        target_id="society",
        state=InterestState.FAVORITE,
    )

    assert await _count(db_session, UserProfile, user_id) == 1
    fav = (
        await db_session.execute(
            select(UserFavoriteInterest).where(UserFavoriteInterest.user_id == user_id)
        )
    ).scalar_one()
    assert fav.interest_slug == "society"


@pytest.mark.asyncio
async def test_existing_profile_is_not_duplicated(db_session):
    """Non-régression : profil et streak existants ne sont ni dupliqués ni écrasés."""
    user_id = uuid4()
    db_session.add(UserProfile(id=uuid4(), user_id=user_id, onboarding_completed=True))
    await db_session.commit()

    source = await _make_source(db_session)
    service = UserSourcesStateService(db_session)

    await service.set_state(user_id, source.id, InterestState.FAVORITE)
    await service.set_state(user_id, source.id, InterestState.FOLLOWED)

    assert await _count(db_session, UserProfile, user_id) == 1
    assert await _count(db_session, UserStreak, user_id) == 1
    assert await _count(db_session, UserFavoriteSource, user_id) == 0
    profile = (
        await db_session.execute(
            select(UserProfile).where(UserProfile.user_id == user_id)
        )
    ).scalar_one()
    assert profile.onboarding_completed is True


@pytest.mark.asyncio
async def test_patch_sources_returns_200_without_profile(db_session):
    """Le chemin exact remonté par Sentry, bout-en-bout.

    Les tests router existants sèment tous un `UserProfile` via leur fixture :
    aucun ne rejouait le 500. Ici le `commit()` du endpoint est le point d'échec
    d'origine, donc seul un passage par la stack HTTP le verrouille.
    """
    user_id = uuid4()
    source = await _make_source(db_session)

    async def _fake_user():
        return str(user_id)

    async def _fake_db():
        yield db_session

    app.dependency_overrides[get_current_user_id] = _fake_user
    app.dependency_overrides[get_db] = _fake_db
    try:
        with patch(
            "app.routers.user_sources_state.get_posthog_client",
            return_value=MagicMock(),
        ):
            async with AsyncClient(
                transport=ASGITransport(app=app), base_url="http://test"
            ) as ac:
                resp = await ac.patch(
                    "/api/user/sources",
                    json={"source_id": str(source.id), "state": "favorite"},
                )
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)
        app.dependency_overrides.pop(get_db, None)

    assert resp.status_code == 200
    assert resp.json()["favorite_count"] == 1
    assert await _count(db_session, UserProfile, user_id) == 1
