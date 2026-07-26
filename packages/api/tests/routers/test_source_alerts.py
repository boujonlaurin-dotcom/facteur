"""Toggle de cloche + écran « Mes alertes » (story 30.2)."""

from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select

from app.database import get_db
from app.dependencies import get_current_user_id
from app.main import app
from app.models.content import Content
from app.models.enums import ContentType, InterestState, SourceType
from app.models.push_notification import PushDelivery, PushDevice
from app.models.source import Source, UserSource
from app.models.user import UserProfile
from app.services.source_alert_producer import ALERT_CAP, source_alert_kind

NOW = datetime.now(UTC)


@pytest_asyncio.fixture
async def alert_user(db_session):
    user_id = uuid4()
    db_session.add(
        UserProfile(
            user_id=user_id,
            display_name="Alert Router User",
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


async def _seed_source(
    db_session,
    user_id,
    *,
    name="Le Mensuel",
    articles=2,
    followed=True,
    oldest_days=29,
):
    source = Source(
        id=uuid4(),
        name=name,
        url=f"https://{uuid4()}.example.com",
        feed_url=f"https://{uuid4()}.example.com/feed.xml",
        type=SourceType.ARTICLE,
        theme="society",
        is_active=True,
        is_curated=True,
    )
    db_session.add(source)
    await db_session.flush()
    for i in range(articles):
        # Le plus ancien fixe la fenêtre du clamp, les autres se répartissent
        # dans les 24 h pour rester « frais ».
        age = timedelta(days=oldest_days) if i == 0 else timedelta(hours=i)
        db_session.add(
            Content(
                id=uuid4(),
                source_id=source.id,
                title=f"{name} — article {i}",
                url=f"https://example.com/{uuid4()}",
                guid=str(uuid4()),
                published_at=NOW - age,
                content_type=ContentType.ARTICLE,
                theme="society",
            )
        )
    if followed:
        db_session.add(
            UserSource(
                user_id=user_id,
                source_id=source.id,
                state=InterestState.FOLLOWED,
            )
        )
    await db_session.commit()
    return source


def _client():
    return AsyncClient(transport=ASGITransport(app=app), base_url="http://test")


@pytest.mark.asyncio
async def test_enable_alert_on_rare_source(alert_user, db_session):
    source = await _seed_source(db_session, alert_user)

    async with _client() as client:
        response = await client.put(
            f"/api/sources/{source.id}/alert", json={"enabled": True}
        )

    assert response.status_code == 200
    assert response.json() == {"enabled": True, "active_count": 1, "cap": ALERT_CAP}

    user_source = await db_session.scalar(
        select(UserSource).where(UserSource.source_id == source.id)
    )
    assert user_source.notify is True


@pytest.mark.asyncio
async def test_disable_alert_needs_no_rarity_check(alert_user, db_session):
    """Une source devenue bavarde ne doit pas piéger sa propre cloche."""
    source = await _seed_source(db_session, alert_user, articles=40, oldest_days=29)
    user_source = await db_session.scalar(
        select(UserSource).where(UserSource.source_id == source.id)
    )
    user_source.notify = True
    await db_session.commit()

    async with _client() as client:
        response = await client.put(
            f"/api/sources/{source.id}/alert", json={"enabled": False}
        )

    assert response.status_code == 200
    assert response.json()["enabled"] is False
    assert response.json()["active_count"] == 0


@pytest.mark.asyncio
async def test_unknown_source_returns_404(alert_user):
    async with _client() as client:
        response = await client.put(
            f"/api/sources/{uuid4()}/alert", json={"enabled": True}
        )
    assert response.status_code == 404


@pytest.mark.asyncio
async def test_not_followed_source_returns_409(alert_user, db_session):
    source = await _seed_source(db_session, alert_user, followed=False)

    async with _client() as client:
        response = await client.put(
            f"/api/sources/{source.id}/alert", json={"enabled": True}
        )

    assert response.status_code == 409
    assert response.json()["detail"]["error"] == "not_followed"


@pytest.mark.asyncio
async def test_chatty_source_returns_422(alert_user, db_session):
    source = await _seed_source(db_session, alert_user, articles=40, oldest_days=29)

    async with _client() as client:
        response = await client.put(
            f"/api/sources/{source.id}/alert", json={"enabled": True}
        )

    assert response.status_code == 422
    assert response.json()["detail"]["error"] == "source_not_rare"


@pytest.mark.asyncio
async def test_cap_is_enforced_at_five(alert_user, db_session):
    sources = [
        await _seed_source(db_session, alert_user, name=f"Revue {i}")
        for i in range(ALERT_CAP + 1)
    ]

    async with _client() as client:
        for source in sources[:ALERT_CAP]:
            ok = await client.put(
                f"/api/sources/{source.id}/alert", json={"enabled": True}
            )
            assert ok.status_code == 200

        refused = await client.put(
            f"/api/sources/{sources[-1].id}/alert", json={"enabled": True}
        )

    assert refused.status_code == 409
    assert refused.json()["detail"] == {
        "error": "alert_cap_reached",
        "cap": ALERT_CAP,
    }


@pytest.mark.asyncio
async def test_re_enabling_an_active_alert_does_not_consume_cap(alert_user, db_session):
    """Idempotence : réactiver une cloche déjà posée ne bute pas sur le plafond."""
    sources = [
        await _seed_source(db_session, alert_user, name=f"Revue {i}")
        for i in range(ALERT_CAP)
    ]

    async with _client() as client:
        for source in sources:
            await client.put(f"/api/sources/{source.id}/alert", json={"enabled": True})
        again = await client.put(
            f"/api/sources/{sources[0].id}/alert", json={"enabled": True}
        )

    assert again.status_code == 200
    assert again.json()["active_count"] == ALERT_CAP


@pytest.mark.asyncio
async def test_list_alerts_reports_silence_and_fresh_content(alert_user, db_session):
    source = await _seed_source(db_session, alert_user)
    user_source = await db_session.scalar(
        select(UserSource).where(UserSource.source_id == source.id)
    )
    user_source.notify = True

    device_id = uuid4()
    db_session.add(
        PushDevice(
            device_id=device_id,
            user_id=alert_user,
            fcm_token="alerts-token",
            platform="android",
            timezone="Europe/Paris",
        )
    )
    await db_session.flush()
    sent_at = NOW - timedelta(days=3)
    db_session.add(
        PushDelivery(
            device_id=device_id,
            target_date=sent_at.date(),
            kind=source_alert_kind(source.id),
            status="sent",
            sent_at=sent_at,
        )
    )
    await db_session.commit()

    async with _client() as client:
        response = await client.get("/api/alerts")

    assert response.status_code == 200
    payload = response.json()
    assert payload["cap"] == ALERT_CAP
    assert payload["active_count"] == 1
    item = payload["items"][0]
    assert item["source_id"] == str(source.id)
    assert item["source_name"] == "Le Mensuel"
    assert item["articles_30d"] == 2
    assert item["last_published_at"] is not None
    assert item["last_alert_sent_at"] is not None
    # 1 article publié il y a 1 h, non lu.
    assert item["new_content"] == 1


@pytest.mark.asyncio
async def test_list_alerts_is_empty_without_bells(alert_user, db_session):
    await _seed_source(db_session, alert_user)

    async with _client() as client:
        response = await client.get("/api/alerts")

    assert response.status_code == 200
    assert response.json() == {"cap": ALERT_CAP, "active_count": 0, "items": []}
