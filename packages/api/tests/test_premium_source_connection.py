from uuid import uuid4

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.enums import InterestState, SourceType
from app.models.source import Source, UserSource
from app.schemas.source import PremiumConnectionResponse
from app.services.source_service import PremiumConnectionNotEnabled, SourceService


def test_premium_connection_response_requires_enabled_usable_urls():
    assert PremiumConnectionResponse.from_config(None) is None
    assert PremiumConnectionResponse.from_config({"enabled": False}) is None
    assert (
        PremiumConnectionResponse.from_config(
            {"enabled": True, "login_url": "https://login.example.com"}
        )
        is None
    )

    response = PremiumConnectionResponse.from_config(
        {
            "enabled": True,
            "login_url": " https://login.example.com ",
            "test_url": " https://example.com/test ",
            "display_hint": " Connectez-vous ",
        }
    )

    assert response is not None
    assert response.login_url == "https://login.example.com"
    assert response.test_url == "https://example.com/test"
    assert response.display_hint == "Connectez-vous"


@pytest.mark.asyncio
async def test_source_response_exposes_enabled_premium_config(
    db_session: AsyncSession,
):
    source = Source(
        id=uuid4(),
        name="Premium Source",
        url="https://example.com",
        feed_url=f"https://example.com/feed-{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="society",
        is_curated=True,
        is_active=True,
        premium_connection_config={
            "enabled": True,
            "login_url": "https://example.com/login",
            "test_url": "https://example.com/premium-test",
        },
    )
    hidden_source = Source(
        id=uuid4(),
        name="Hidden Premium Source",
        url="https://hidden.example.com",
        feed_url=f"https://hidden.example.com/feed-{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="society",
        is_curated=True,
        is_active=True,
        premium_connection_config={
            "enabled": True,
            "login_url": "https://hidden.example.com/login",
        },
    )
    db_session.add_all([source, hidden_source])
    await db_session.flush()

    responses = await SourceService(db_session).get_curated_sources()
    by_id = {response.id: response for response in responses}

    assert by_id[source.id].premium_connection is not None
    assert by_id[source.id].premium_connection.login_url == "https://example.com/login"
    assert by_id[hidden_source.id].premium_connection is None


@pytest.mark.asyncio
async def test_subscription_true_creates_user_source_and_timestamps(
    db_session: AsyncSession,
):
    user_id = uuid4()
    source = Source(
        id=uuid4(),
        name="Premium Source",
        url="https://example.com",
        feed_url=f"https://example.com/feed-{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="society",
        is_curated=True,
        is_active=True,
        premium_connection_config={
            "enabled": True,
            "login_url": "https://example.com/login",
            "test_url": "https://example.com/premium-test",
        },
    )
    db_session.add(source)
    await db_session.flush()

    response = await SourceService(db_session).update_source_subscription(
        str(user_id), str(source.id), True
    )

    user_source = await db_session.scalar(
        select(UserSource).where(
            UserSource.user_id == user_id,
            UserSource.source_id == source.id,
        )
    )
    assert response is not None
    assert response.has_subscription is True
    assert response.is_trusted is True
    assert user_source is not None
    assert user_source.has_subscription is True
    assert user_source.state == InterestState.FOLLOWED
    assert user_source.subscription_connected_at is not None
    assert user_source.subscription_last_verified_at is not None


@pytest.mark.asyncio
async def test_subscription_false_clears_timestamps(db_session: AsyncSession):
    user_id = uuid4()
    source = Source(
        id=uuid4(),
        name="Premium Source",
        url="https://example.com",
        feed_url=f"https://example.com/feed-{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="society",
        is_curated=True,
        is_active=True,
        premium_connection_config={
            "enabled": True,
            "login_url": "https://example.com/login",
            "test_url": "https://example.com/premium-test",
        },
    )
    user_source = UserSource(
        user_id=user_id,
        source=source,
        has_subscription=True,
    )
    db_session.add_all([source, user_source])
    await db_session.flush()

    response = await SourceService(db_session).update_source_subscription(
        str(user_id), str(source.id), False
    )

    assert response is not None
    assert response.has_subscription is False
    assert user_source.has_subscription is False
    assert user_source.subscription_connected_at is None
    assert user_source.subscription_last_verified_at is None


@pytest.mark.asyncio
async def test_subscription_true_rejects_non_allowlisted_source(
    db_session: AsyncSession,
):
    source = Source(
        id=uuid4(),
        name="Regular Source",
        url="https://example.com",
        feed_url=f"https://example.com/feed-{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="society",
        is_curated=True,
        is_active=True,
    )
    db_session.add(source)
    await db_session.flush()

    with pytest.raises(PremiumConnectionNotEnabled):
        await SourceService(db_session).update_source_subscription(
            str(uuid4()), str(source.id), True
        )
