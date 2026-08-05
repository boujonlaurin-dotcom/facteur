"""`POST /api/analytics/events/batch` — lot d'events en un seul commit.

Chemin d'ingestion du dénominateur du CTR (`article_impression`) : une session
de lecture en produit ~30, que le client bufferise puis pousse en un POST.
"""

from uuid import uuid4

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select

from app.database import get_db
from app.dependencies import get_current_user_id
from app.main import app
from app.models.analytics import AnalyticsEvent
from app.routers.analytics import MAX_BATCH_EVENTS
from app.services.recommendation.scoring_config import scoring_algo_version


def _override_db(session):
    async def _fake_db():
        yield session

    return _fake_db


def _override_user(user_id: str):
    async def _fake_user():
        return user_id

    return _fake_user


def _impression(index: int) -> dict:
    return {
        "event_type": "article_impression",
        "event_data": {
            "content_id": f"content-{index}",
            "section_key": "theme:politique",
            "section_family": "theme",
            "position_in_section": index,
        },
        "device_id": "device-1",
    }


async def _post_batch(db_session, user_id, payload):
    app.dependency_overrides[get_current_user_id] = _override_user(str(user_id))
    app.dependency_overrides[get_db] = _override_db(db_session)
    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            return await ac.post("/api/analytics/events/batch", json=payload)
    finally:
        app.dependency_overrides.clear()


@pytest.mark.asyncio
async def test_batch_persists_every_event(db_session):
    user_id = uuid4()

    response = await _post_batch(
        db_session, user_id, [_impression(i) for i in range(25)]
    )

    assert response.status_code == 201
    assert response.json()["accepted"] == 25

    rows = (
        (
            await db_session.execute(
                select(AnalyticsEvent).where(AnalyticsEvent.user_id == user_id)
            )
        )
        .scalars()
        .all()
    )
    assert len(rows) == 25
    assert {row.event_type for row in rows} == {"article_impression"}
    assert {row.device_id for row in rows} == {"device-1"}


@pytest.mark.asyncio
async def test_batch_at_cap_is_accepted_and_over_cap_is_rejected(db_session):
    user_id = uuid4()

    at_cap = await _post_batch(
        db_session, user_id, [_impression(i) for i in range(MAX_BATCH_EVENTS)]
    )
    assert at_cap.status_code == 201
    assert at_cap.json()["accepted"] == MAX_BATCH_EVENTS

    over_cap = await _post_batch(
        db_session, user_id, [_impression(i) for i in range(MAX_BATCH_EVENTS + 1)]
    )
    assert over_cap.status_code == 422

    # Le lot refusé n'a rien écrit : seul le lot au cap est en base.
    count = (
        (
            await db_session.execute(
                select(AnalyticsEvent).where(AnalyticsEvent.user_id == user_id)
            )
        )
        .scalars()
        .all()
    )
    assert len(count) == MAX_BATCH_EVENTS


@pytest.mark.asyncio
async def test_partial_event_data_does_not_fail_the_batch(db_session):
    """Un event aux propriétés incomplètes passe : `event_data` est un JSONB
    libre, une carte sans score ne doit pas faire tomber les 24 autres."""
    user_id = uuid4()

    response = await _post_batch(
        db_session,
        user_id,
        [
            {"event_type": "article_impression", "event_data": {}},
            _impression(1),
            {"event_type": "article_impression", "event_data": {"content_id": "x"}},
        ],
    )

    assert response.status_code == 201
    assert response.json()["accepted"] == 3


@pytest.mark.asyncio
async def test_impressions_are_stamped_with_the_active_algo_version(db_session):
    user_id = uuid4()

    await _post_batch(
        db_session,
        user_id,
        [
            _impression(0),
            # Version déjà posée par le client → jamais écrasée.
            {
                "event_type": "article_impression",
                "event_data": {"content_id": "c", "algo_version": "pinned_by_client"},
            },
            # Event non-impression → pas d'estampille (l'algo ne le concerne pas).
            {"event_type": "feed_scroll", "event_data": {"depth": 3}},
        ],
    )

    rows = (
        (
            await db_session.execute(
                select(AnalyticsEvent).where(AnalyticsEvent.user_id == user_id)
            )
        )
        .scalars()
        .all()
    )
    by_content = {row.event_data.get("content_id"): row for row in rows}

    assert by_content["content-0"].event_data["algo_version"] == scoring_algo_version()
    assert by_content["c"].event_data["algo_version"] == "pinned_by_client"
    assert "algo_version" not in by_content[None].event_data


@pytest.mark.asyncio
async def test_empty_batch_is_a_noop(db_session):
    user_id = uuid4()

    response = await _post_batch(db_session, user_id, [])

    assert response.status_code == 201
    assert response.json()["accepted"] == 0
