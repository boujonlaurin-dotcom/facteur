"""Tests de POST /api/sources/recent-items (animation de conclusion onboarding).

Vérifie le groupement par source, le cap per_source, les bornes du schéma,
l'omission des sources inconnues et l'auth.
"""

from datetime import datetime, timedelta, timezone
from uuid import uuid4

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient

from app.database import get_db
from app.dependencies import get_current_user_id
from app.main import app
from app.models.content import Content
from app.models.enums import ContentType, SourceType
from app.models.source import Source

BASE_DT = datetime(2026, 6, 1, 12, 0, tzinfo=timezone.utc)


def _make_source(name: str) -> Source:
    return Source(
        id=uuid4(),
        name=name,
        url=f"https://{name.lower().replace(' ', '')}.example.com",
        feed_url=f"https://{name.lower().replace(' ', '')}.example.com/feed-{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme="society",
        logo_url=f"https://{name.lower().replace(' ', '')}.example.com/logo.png",
        is_active=True,
        is_curated=True,
    )


def _make_content(source_id, title: str, age_hours: int) -> Content:
    return Content(
        id=uuid4(),
        source_id=source_id,
        title=title,
        url=f"https://example.com/{uuid4()}",
        published_at=BASE_DT - timedelta(hours=age_hours),
        content_type=ContentType.ARTICLE,
        guid=str(uuid4()),
    )


@pytest_asyncio.fixture
async def auth_client(db_session):
    user_id = uuid4()

    async def _fake_user():
        return str(user_id)

    async def _fake_db():
        yield db_session

    app.dependency_overrides[get_current_user_id] = _fake_user
    app.dependency_overrides[get_db] = _fake_db
    transport = ASGITransport(app=app)
    try:
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            yield ac
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)
        app.dependency_overrides.pop(get_db, None)


@pytest.mark.asyncio
async def test_groups_items_by_source_ordered_desc(auth_client, db_session):
    s1, s2 = _make_source("Le Monde"), _make_source("Liberation")
    db_session.add_all([s1, s2])
    await db_session.flush()
    db_session.add_all(
        [
            _make_content(s1.id, "S1 vieux", age_hours=10),
            _make_content(s1.id, "S1 recent", age_hours=1),
            _make_content(s2.id, "S2 seul", age_hours=5),
        ]
    )
    await db_session.commit()

    resp = await auth_client.post(
        "/api/sources/recent-items",
        json={"source_ids": [str(s2.id), str(s1.id)]},
    )
    assert resp.status_code == 200
    sources = resp.json()["sources"]
    assert [s["name"] for s in sources] == ["Liberation", "Le Monde"]
    assert sources[0]["logo_url"] == s2.logo_url
    assert [i["title"] for i in sources[1]["items"]] == ["S1 recent", "S1 vieux"]
    assert sources[1]["items"][0]["published_at"].startswith("2026-06-01T11:00")


@pytest.mark.asyncio
async def test_caps_items_per_source(auth_client, db_session):
    source = _make_source("Prolifique")
    db_session.add(source)
    await db_session.flush()
    db_session.add_all(
        [_make_content(source.id, f"Article {i}", age_hours=i) for i in range(6)]
    )
    await db_session.commit()

    resp = await auth_client.post(
        "/api/sources/recent-items",
        json={"source_ids": [str(source.id)], "per_source": 3},
    )
    assert resp.status_code == 200
    items = resp.json()["sources"][0]["items"]
    assert [i["title"] for i in items] == ["Article 0", "Article 1", "Article 2"]


@pytest.mark.asyncio
async def test_schema_caps_rejected(auth_client):
    resp = await auth_client.post(
        "/api/sources/recent-items",
        json={"source_ids": [str(uuid4())], "per_source": 6},
    )
    assert resp.status_code == 422

    resp = await auth_client.post(
        "/api/sources/recent-items",
        json={"source_ids": [str(uuid4()) for _ in range(31)]},
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_empty_source_ids_returns_empty(auth_client):
    resp = await auth_client.post(
        "/api/sources/recent-items",
        json={"source_ids": []},
    )
    assert resp.status_code == 200
    assert resp.json() == {"sources": []}


@pytest.mark.asyncio
async def test_unknown_source_omitted(auth_client, db_session):
    source = _make_source("Connue")
    db_session.add(source)
    await db_session.flush()
    db_session.add(_make_content(source.id, "Article", age_hours=1))
    await db_session.commit()

    resp = await auth_client.post(
        "/api/sources/recent-items",
        json={"source_ids": [str(uuid4()), str(source.id)]},
    )
    assert resp.status_code == 200
    sources = resp.json()["sources"]
    assert len(sources) == 1
    assert sources[0]["name"] == "Connue"


@pytest.mark.asyncio
async def test_requires_auth():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        resp = await ac.post(
            "/api/sources/recent-items",
            json={"source_ids": [str(uuid4())]},
        )
    assert resp.status_code in (401, 403)
