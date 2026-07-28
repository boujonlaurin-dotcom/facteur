"""Toggle de cloche sujet + devis de cadence (story 30.3 « alertes v2 »)."""

from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from app.database import get_db
from app.dependencies import get_current_user_id
from app.main import app
from app.models.content import Content
from app.models.enums import ContentType, InterestState, SourceType
from app.models.source import Source, UserSource
from app.models.user import UserProfile
from app.models.user_topic_profile import UserTopicProfile
from app.services.alert_cadence import ALERT_CAP

NOW = datetime.now(UTC)


@pytest_asyncio.fixture
async def alert_user(db_session):
    user_id = uuid4()
    db_session.add(
        UserProfile(
            user_id=user_id,
            display_name="Topic Alert User",
            onboarding_completed=True,
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


async def _seed_topic(
    db_session,
    user_id,
    *,
    name="Ligue 1",
    state=InterestState.FOLLOWED,
) -> UserTopicProfile:
    profile = UserTopicProfile(
        user_id=user_id,
        topic_name=name,
        slug_parent="sport",
        canonical_name=name,
        keywords=[],
        state=state,
    )
    db_session.add(profile)
    await db_session.commit()
    return profile


async def _seed_matching_articles(db_session, *, count: int, entity: str = "Ligue 1"):
    source = Source(
        id=uuid4(),
        name="Source",
        url=f"https://{uuid4()}.example.com",
        feed_url=f"https://{uuid4()}.example.com/feed.xml",
        type=SourceType.ARTICLE,
        theme="sport",
        is_active=True,
        is_curated=True,
    )
    db_session.add(source)
    await db_session.flush()
    for i in range(count):
        db_session.add(
            Content(
                id=uuid4(),
                source_id=source.id,
                title=f"Match {i}",
                url=f"https://example.com/{uuid4()}",
                guid=str(uuid4()),
                # Étalés sur 29 j pour que le clamp de fenêtre ne les concentre
                # pas sur une journée.
                published_at=NOW - timedelta(days=29 * i / max(count - 1, 1)),
                content_type=ContentType.ARTICLE,
                theme="sport",
                entities=[f'{{"name": "{entity}", "type": "EVENT"}}'],
            )
        )
    await db_session.commit()
    return source


def _client():
    return AsyncClient(transport=ASGITransport(app=app), base_url="http://test")


@pytest.mark.asyncio
async def test_enable_topic_alert(alert_user, db_session):
    topic = await _seed_topic(db_session, alert_user)

    async with _client() as client:
        response = await client.put(
            f"/api/personalization/topics/{topic.id}/alert", json={"enabled": True}
        )

    assert response.status_code == 200
    assert response.json() == {
        "enabled": True,
        "filtered": False,
        "active_count": 1,
        "cap": ALERT_CAP,
    }

    await db_session.refresh(topic)
    assert topic.notify is True


@pytest.mark.asyncio
async def test_enable_topic_alert_in_filtered_mode(alert_user, db_session):
    topic = await _seed_topic(db_session, alert_user)

    async with _client() as client:
        response = await client.put(
            f"/api/personalization/topics/{topic.id}/alert",
            json={"enabled": True, "filtered": True},
        )

    assert response.json()["filtered"] is True
    await db_session.refresh(topic)
    assert topic.notify_filtered is True


@pytest.mark.asyncio
async def test_unknown_topic_returns_404(alert_user):
    async with _client() as client:
        response = await client.put(
            f"/api/personalization/topics/{uuid4()}/alert", json={"enabled": True}
        )
    assert response.status_code == 404


@pytest.mark.asyncio
async def test_unfollowed_topic_returns_409(alert_user, db_session):
    topic = await _seed_topic(db_session, alert_user, state=InterestState.UNFOLLOWED)

    async with _client() as client:
        response = await client.put(
            f"/api/personalization/topics/{topic.id}/alert", json={"enabled": True}
        )

    assert response.status_code == 409
    assert response.json()["detail"]["error"] == "not_followed"


@pytest.mark.asyncio
async def test_cap_is_shared_with_source_alerts(alert_user, db_session):
    """5 cloches en tout : 5 sources saturent le plafond des sujets."""
    for i in range(ALERT_CAP):
        source = Source(
            id=uuid4(),
            name=f"Revue {i}",
            url=f"https://{uuid4()}.example.com",
            feed_url=f"https://{uuid4()}.example.com/feed.xml",
            type=SourceType.ARTICLE,
            theme="society",
            is_active=True,
            is_curated=True,
        )
        db_session.add(source)
        await db_session.flush()
        db_session.add(
            UserSource(
                user_id=alert_user,
                source_id=source.id,
                state=InterestState.FOLLOWED,
                notify=True,
            )
        )
    topic = await _seed_topic(db_session, alert_user)

    async with _client() as client:
        response = await client.put(
            f"/api/personalization/topics/{topic.id}/alert", json={"enabled": True}
        )

    assert response.status_code == 409
    assert response.json()["detail"] == {
        "error": "alert_cap_reached",
        "cap": ALERT_CAP,
    }


@pytest.mark.asyncio
async def test_frequency_endpoint_quotes_the_noise(alert_user, db_session):
    topic = await _seed_topic(db_session, alert_user)
    await _seed_matching_articles(db_session, count=30)

    async with _client() as client:
        response = await client.get(f"/api/personalization/topics/{topic.id}/frequency")

    assert response.status_code == 200
    payload = response.json()
    assert payload["articles_30d"] == 30
    assert payload["noisy"] is True
    assert payload["cadence_phrase"].startswith("Publie environ")


@pytest.mark.asyncio
async def test_frequency_endpoint_on_a_quiet_topic(alert_user, db_session):
    topic = await _seed_topic(db_session, alert_user)
    await _seed_matching_articles(db_session, count=2)

    async with _client() as client:
        response = await client.get(f"/api/personalization/topics/{topic.id}/frequency")

    payload = response.json()
    assert payload["articles_30d"] == 2
    assert payload["noisy"] is False


@pytest.mark.asyncio
async def test_list_alerts_unions_both_families(alert_user, db_session):
    topic = await _seed_topic(db_session, alert_user)
    topic.notify = True
    source = Source(
        id=uuid4(),
        name="Le Mensuel",
        url=f"https://{uuid4()}.example.com",
        feed_url=f"https://{uuid4()}.example.com/feed.xml",
        type=SourceType.ARTICLE,
        theme="society",
        is_active=True,
        is_curated=True,
    )
    db_session.add(source)
    await db_session.flush()
    db_session.add(
        UserSource(
            user_id=alert_user,
            source_id=source.id,
            state=InterestState.FOLLOWED,
            notify=True,
        )
    )
    await db_session.commit()

    async with _client() as client:
        response = await client.get("/api/alerts")

    payload = response.json()
    assert payload["active_count"] == 2
    assert {i["kind"] for i in payload["items"]} == {"source", "topic"}
    topic_item = next(i for i in payload["items"] if i["kind"] == "topic")
    assert topic_item["source_id"] == str(topic.id)
    assert topic_item["source_name"] == "Ligue 1"
