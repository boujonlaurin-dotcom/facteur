"""Tests fraîcheur de GET /api/sources/by-theme/{slug} — écran onboarding.

Verrouille le garde-fou de fraîcheur du levier prioritaire :
- un flux `article` sans article récent (feed mort) est écarté des Curées ;
- une source `article` fraîche est conservée ;
- une source à cadence lente (`podcast`/`youtube`) silencieuse sur 30 j mais
  active sur 90 j est conservée mais **déclassée** (après les fraîches).
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
    BiasStance,
    ContentType,
    ReliabilityScore,
    SourceType,
)
from app.models.source import Source


def _source(name, *, source_type=SourceType.ARTICLE, theme="tech"):
    slug = name.lower().replace(" ", "")
    return Source(
        id=uuid4(),
        name=name,
        url=f"https://{slug}.example.com",
        feed_url=f"https://{slug}.example.com/feed-{uuid4()}.xml",
        type=source_type,
        theme=theme,
        is_active=True,
        is_curated=True,
        bias_stance=BiasStance.CENTER,
        reliability_score=ReliabilityScore.HIGH,
    )


def _article(source, *, days_ago):
    return Content(
        id=uuid4(),
        source_id=source.id,
        title=f"Article {source.name}",
        url=f"{source.url}/a-{uuid4()}",
        published_at=datetime.now(UTC) - timedelta(days=days_ago),
        content_type=ContentType.ARTICLE,
        guid=str(uuid4()),
    )


@pytest_asyncio.fixture
async def client(db_session):
    async def _fake_user():
        return str(uuid4())

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


def _curated_names(body):
    for group in body["groups"]:
        if group["label"] == "Curées":
            return [s["name"] for s in group["sources"]]
    return []


@pytest.mark.asyncio
async def test_dead_article_feed_excluded(client, db_session):
    alive = _source("Alive")
    dead = _source("Dead")
    db_session.add_all([alive, dead])
    await db_session.flush()
    db_session.add(_article(alive, days_ago=1))  # dead : aucun article
    await db_session.commit()

    resp = await client.get("/api/sources/by-theme/tech")
    assert resp.status_code == 200
    names = _curated_names(resp.json())
    assert "Alive" in names
    assert "Dead" not in names


@pytest.mark.asyncio
async def test_slow_source_kept_but_downgraded(client, db_session):
    fresh = _source("Fresh Article")
    slow = _source("Slow Podcast", source_type=SourceType.PODCAST)
    db_session.add_all([fresh, slow])
    await db_session.flush()
    db_session.add(_article(fresh, days_ago=2))
    db_session.add(_article(slow, days_ago=45))  # silencieux 30j, actif 90j
    await db_session.commit()

    resp = await client.get("/api/sources/by-theme/tech")
    assert resp.status_code == 200
    names = _curated_names(resp.json())
    assert names.index("Fresh Article") < names.index("Slow Podcast")
