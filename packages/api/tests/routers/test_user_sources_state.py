"""Tests des nouveaux endpoints `/api/user/sources` (Story 22.1).

Symétrique de test_user_interests.py mais sans XOR (pas de custom topic).
"""

from unittest.mock import MagicMock, patch
from uuid import uuid4

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from app.constants import FAVORITE_CAP
from app.database import get_db
from app.dependencies import get_current_user_id
from app.main import app
from app.models.enums import InterestState, SourceType
from app.models.source import Source, UserSource
from app.models.user import UserProfile


@pytest_asyncio.fixture
async def auth_user_with_sources(db_session):
    user_id = uuid4()
    db_session.add(UserProfile(user_id=user_id, onboarding_completed=True))
    sources = []
    for i in range(4):
        s = Source(
            id=uuid4(),
            name=f"Source {i}",
            url=f"https://s{i}.example.com",
            feed_url=f"https://s{i}.example.com/feed.xml",
            type=SourceType.ARTICLE,
            theme="society",
            is_active=True,
            is_curated=False,
        )
        db_session.add(s)
        sources.append(s)
    await db_session.flush()
    for s in sources:
        db_session.add(
            UserSource(
                user_id=user_id,
                source_id=s.id,
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
        yield user_id, sources
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)
        app.dependency_overrides.pop(get_db, None)


@pytest.mark.asyncio
async def test_get_returns_sources_and_empty_favorites(auth_user_with_sources):
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        resp = await ac.get("/api/user/sources")
    assert resp.status_code == 200
    body = resp.json()
    assert len(body["sources"]) == 4
    assert body["favorite_count"] == 0
    assert body["favorite_cap"] == FAVORITE_CAP


@pytest.mark.asyncio
async def test_patch_promotes_source_to_favorite(auth_user_with_sources):
    _, sources = auth_user_with_sources
    transport = ASGITransport(app=app)
    with patch(
        "app.routers.user_sources_state.get_posthog_client",
        return_value=MagicMock(),
    ):
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            resp = await ac.patch(
                "/api/user/sources",
                json={"source_id": str(sources[0].id), "state": "favorite"},
            )
    assert resp.status_code == 200
    body = resp.json()
    assert body["favorite_count"] == 1


@pytest.mark.asyncio
async def test_source_cap_reached(auth_user_with_sources):
    _, sources = auth_user_with_sources
    transport = ASGITransport(app=app)
    with patch(
        "app.routers.user_sources_state.get_posthog_client",
        return_value=MagicMock(),
    ):
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            for s in sources[:FAVORITE_CAP]:
                ok = await ac.patch(
                    "/api/user/sources",
                    json={"source_id": str(s.id), "state": "favorite"},
                )
                assert ok.status_code == 200, ok.text
            ko = await ac.patch(
                "/api/user/sources",
                json={"source_id": str(sources[3].id), "state": "favorite"},
            )
    assert ko.status_code == 422
    assert ko.json()["detail"] == {
        "error": "favorite_cap_reached",
        "cap": FAVORITE_CAP,
    }
