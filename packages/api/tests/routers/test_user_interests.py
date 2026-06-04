"""Tests des nouveaux endpoints `/api/user/interests` (Story 22.1).

Couvre : GET (liste vide / avec favoris), PATCH (followed→favorite, cap=5),
POST /reorder (transactionnel + refus si target n'est pas favorite),
auto-création de UserInterest si l'user n'avait pas la row.
"""

from unittest.mock import MagicMock, patch
from uuid import uuid4

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select

from app.constants import FAVORITE_CAP
from app.database import get_db
from app.dependencies import get_current_user_id
from app.main import app
from app.models.enums import InterestState
from app.models.user import UserInterest, UserProfile
from app.models.user_favorites import UserFavoriteInterest
from app.models.user_topic_profile import UserTopicProfile
from app.models.veille import VeilleConfig, VeilleStatus


@pytest_asyncio.fixture
async def auth_user(db_session):
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
async def auth_user_with_themes(db_session, auth_user):
    """User avec 6 thèmes followed (assez pour dépasser le cap d'affichage=5)."""
    for slug in ("tech", "society", "culture", "science", "economy", "politics"):
        db_session.add(
            UserInterest(
                user_id=auth_user,
                interest_slug=slug,
                weight=1.0,
                state=InterestState.FOLLOWED,
            )
        )
    await db_session.commit()
    return auth_user


@pytest.mark.asyncio
async def test_get_returns_empty_state_for_blank_user(auth_user):
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        resp = await ac.get("/api/user/interests")
    assert resp.status_code == 200
    body = resp.json()
    assert body["themes"] == []
    assert body["custom_topics"] == []
    assert body["favorites"] == []
    assert body["favorite_count"] == 0
    assert body["favorite_cap"] == FAVORITE_CAP


@pytest.mark.asyncio
async def test_get_interests_returns_veille_favorite(auth_user, db_session):
    """Story 23.1 PR-3 : un favori veille apparaît avec kind=veille et
    target_id = str(veille_config_id)."""
    cfg = VeilleConfig(
        id=uuid4(),
        user_id=auth_user,
        theme_id="tech",
        theme_label="Tech",
        status=VeilleStatus.ACTIVE.value,
    )
    db_session.add(cfg)
    await db_session.flush()
    db_session.add(
        UserFavoriteInterest(
            user_id=auth_user, position=0, veille_config_id=cfg.id
        )
    )
    await db_session.commit()

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        resp = await ac.get("/api/user/interests")
    assert resp.status_code == 200
    body = resp.json()
    assert body["favorite_count"] == 1
    assert body["favorites"][0]["kind"] == "veille"
    assert body["favorites"][0]["target_id"] == str(cfg.id)
    assert body["favorites"][0]["position"] == 0


@pytest.mark.asyncio
async def test_patch_promotes_theme_to_favorite(auth_user_with_themes, db_session):
    transport = ASGITransport(app=app)
    with patch(
        "app.routers.user_interests.get_posthog_client", return_value=MagicMock()
    ) as mock_ph:
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            resp = await ac.patch(
                "/api/user/interests",
                json={"kind": "theme", "target_id": "tech", "state": "favorite"},
            )
    assert resp.status_code == 200
    body = resp.json()
    assert body["favorite_count"] == 1
    assert body["favorites"][0]["target_id"] == "tech"
    assert body["favorites"][0]["position"] == 0

    # PostHog: événement state_changed émis avec prev_state='followed'.
    capture = mock_ph.return_value.capture
    events = [c.kwargs.get("event") for c in capture.call_args_list]
    assert "interest_state_changed" in events


@pytest.mark.asyncio
async def test_patch_accepts_more_than_cap_favorites(
    auth_user_with_themes, db_session
):
    """Story 22.2 — cap retiré : un 6e favori est accepté (position=5)."""
    transport = ASGITransport(app=app)
    with patch(
        "app.routers.user_interests.get_posthog_client", return_value=MagicMock()
    ):
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            for slug in ("tech", "society", "culture", "science", "economy"):
                resp = await ac.patch(
                    "/api/user/interests",
                    json={"kind": "theme", "target_id": slug, "state": "favorite"},
                )
                assert resp.status_code == 200, resp.text

            resp6 = await ac.patch(
                "/api/user/interests",
                json={"kind": "theme", "target_id": "politics", "state": "favorite"},
            )
    assert resp6.status_code == 200, resp6.text
    body = resp6.json()
    assert body["favorite_count"] == 6
    positions = sorted(f["position"] for f in body["favorites"])
    assert positions == [0, 1, 2, 3, 4, 5]


@pytest.mark.asyncio
async def test_patch_creates_interest_implicitly_if_missing(auth_user, db_session):
    """User n'a aucune row UserInterest pour 'environment' → PATCH la crée."""
    transport = ASGITransport(app=app)
    with patch(
        "app.routers.user_interests.get_posthog_client", return_value=MagicMock()
    ):
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            resp = await ac.patch(
                "/api/user/interests",
                json={
                    "kind": "theme",
                    "target_id": "environment",
                    "state": "favorite",
                },
            )
    assert resp.status_code == 200
    rows = (
        (
            await db_session.execute(
                select(UserInterest).where(
                    UserInterest.user_id == auth_user,
                    UserInterest.interest_slug == "environment",
                )
            )
        )
        .scalars()
        .all()
    )
    assert len(rows) == 1
    assert rows[0].state == InterestState.FAVORITE


@pytest.mark.asyncio
async def test_patch_demotes_favorite_removes_row(auth_user_with_themes, db_session):
    """Passer un favori en followed retire la row de user_favorite_interests."""
    transport = ASGITransport(app=app)
    with patch(
        "app.routers.user_interests.get_posthog_client", return_value=MagicMock()
    ):
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            await ac.patch(
                "/api/user/interests",
                json={"kind": "theme", "target_id": "tech", "state": "favorite"},
            )
            resp = await ac.patch(
                "/api/user/interests",
                json={"kind": "theme", "target_id": "tech", "state": "followed"},
            )
    assert resp.status_code == 200
    favs = (
        (
            await db_session.execute(
                select(UserFavoriteInterest).where(
                    UserFavoriteInterest.user_id == auth_user_with_themes
                )
            )
        )
        .scalars()
        .all()
    )
    assert favs == []


@pytest.mark.asyncio
async def test_reorder_swaps_positions(auth_user_with_themes, db_session):
    transport = ASGITransport(app=app)
    with patch(
        "app.routers.user_interests.get_posthog_client", return_value=MagicMock()
    ):
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            for slug in ("tech", "society", "culture"):
                await ac.patch(
                    "/api/user/interests",
                    json={"kind": "theme", "target_id": slug, "state": "favorite"},
                )

            resp = await ac.post(
                "/api/user/interests/reorder",
                json={
                    "favorites": [
                        {"kind": "theme", "target_id": "culture", "position": 0},
                        {"kind": "theme", "target_id": "tech", "position": 1},
                        {"kind": "theme", "target_id": "society", "position": 2},
                    ]
                },
            )
    assert resp.status_code == 200
    body = resp.json()
    assert [f["target_id"] for f in body["favorites"]] == [
        "culture",
        "tech",
        "society",
    ]


@pytest.mark.asyncio
async def test_patch_allows_favorite_for_custom_topic(auth_user, db_session):
    """bug-custom-topic-favori-regression — un custom_topic peut être épinglé.

    Sémantique côté backend identique à un thème favori (state=favorite + ligne
    dans user_favorite_interests). Côté mobile, ces favoris sont affichés dans
    la section « Sujets épinglés » séparée du top 5 reorderable. La
    `priority_multiplier=2.0` synchronisée permet à `feed.py:get_tab_counts`
    d'alimenter les onglets de la section Explorer.
    """
    topic = UserTopicProfile(
        user_id=auth_user,
        topic_name="Plongée",
        slug_parent="sport",
        state=InterestState.FOLLOWED,
        priority_multiplier=1.0,
    )
    db_session.add(topic)
    await db_session.commit()

    transport = ASGITransport(app=app)
    with patch(
        "app.routers.user_interests.get_posthog_client", return_value=MagicMock()
    ):
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            resp = await ac.patch(
                "/api/user/interests",
                json={
                    "kind": "custom_topic",
                    "target_id": str(topic.id),
                    "state": "favorite",
                },
            )
    assert resp.status_code == 200
    body = resp.json()
    assert any(
        f["kind"] == "custom_topic" and f["target_id"] == str(topic.id)
        for f in body["favorites"]
    )

    await db_session.refresh(topic)
    assert topic.state == InterestState.FAVORITE
    assert topic.priority_multiplier == 2.0


@pytest.mark.asyncio
async def test_patch_unfavorite_custom_topic_resets_multiplier(auth_user, db_session):
    """Désépingler un sujet → state=followed + priority_multiplier=1.0.

    Garantit que les onglets de la section Explorer disparaissent dès la
    transition (feed.py:get_tab_counts filtre sur priority_multiplier==2.0).
    """
    topic = UserTopicProfile(
        user_id=auth_user,
        topic_name="Plongée",
        slug_parent="sport",
        state=InterestState.FAVORITE,
        priority_multiplier=2.0,
    )
    db_session.add(topic)
    await db_session.commit()

    transport = ASGITransport(app=app)
    with patch(
        "app.routers.user_interests.get_posthog_client", return_value=MagicMock()
    ):
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            resp = await ac.patch(
                "/api/user/interests",
                json={
                    "kind": "custom_topic",
                    "target_id": str(topic.id),
                    "state": "followed",
                },
            )
    assert resp.status_code == 200
    body = resp.json()
    assert not any(
        f["kind"] == "custom_topic" and f["target_id"] == str(topic.id)
        for f in body["favorites"]
    )

    await db_session.refresh(topic)
    assert topic.state == InterestState.FOLLOWED
    assert topic.priority_multiplier == 1.0


@pytest.mark.asyncio
async def test_patch_allows_followed_for_custom_topic(auth_user, db_session):
    """Story 23.3 — passer un custom_topic en followed reste OK (boost scoring)."""
    topic = UserTopicProfile(
        user_id=auth_user,
        topic_name="Plongée",
        slug_parent="sport",
        state=InterestState.UNFOLLOWED,
    )
    db_session.add(topic)
    await db_session.commit()

    transport = ASGITransport(app=app)
    with patch(
        "app.routers.user_interests.get_posthog_client", return_value=MagicMock()
    ):
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            resp = await ac.patch(
                "/api/user/interests",
                json={
                    "kind": "custom_topic",
                    "target_id": str(topic.id),
                    "state": "followed",
                },
            )
    assert resp.status_code == 200
    await db_session.refresh(topic)
    assert topic.state == InterestState.FOLLOWED


@pytest.mark.asyncio
async def test_reorder_rejects_custom_topic(auth_user_with_themes, db_session):
    """Un reorder qui inclut un custom_topic → 422 custom_topic_not_reorderable.

    Le top 5 reorderable de la « Tournée du jour » est réservé aux thèmes et
    veilles. Les custom_topic favoris vivent dans la section « Sujets épinglés »
    séparée et ne sont pas draggable dans le top 5.
    """
    topic = UserTopicProfile(
        user_id=auth_user_with_themes,
        topic_name="Plongée",
        slug_parent="sport",
        state=InterestState.FAVORITE,
        priority_multiplier=2.0,
    )
    db_session.add(topic)
    await db_session.commit()

    transport = ASGITransport(app=app)
    with patch(
        "app.routers.user_interests.get_posthog_client", return_value=MagicMock()
    ):
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            await ac.patch(
                "/api/user/interests",
                json={"kind": "theme", "target_id": "tech", "state": "favorite"},
            )
            resp = await ac.post(
                "/api/user/interests/reorder",
                json={
                    "favorites": [
                        {"kind": "theme", "target_id": "tech", "position": 0},
                        {
                            "kind": "custom_topic",
                            "target_id": str(topic.id),
                            "position": 1,
                        },
                    ]
                },
            )
    assert resp.status_code == 422
    assert resp.json()["detail"]["error"] == "custom_topic_not_reorderable"


@pytest.mark.asyncio
async def test_reorder_rejects_non_favorite_target(
    auth_user_with_themes, db_session
):
    """`science` n'est pas favori → reorder doit 422."""
    transport = ASGITransport(app=app)
    with patch(
        "app.routers.user_interests.get_posthog_client", return_value=MagicMock()
    ):
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            await ac.patch(
                "/api/user/interests",
                json={"kind": "theme", "target_id": "tech", "state": "favorite"},
            )
            resp = await ac.post(
                "/api/user/interests/reorder",
                json={
                    "favorites": [
                        {"kind": "theme", "target_id": "tech", "position": 0},
                        {"kind": "theme", "target_id": "science", "position": 1},
                    ]
                },
            )
    assert resp.status_code == 422
