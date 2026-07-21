"""Tests pour /api/health/classification — observabilité du worker ML.

Incident 2026-06-30 : le worker de classification (task asyncio du lifespan)
est mort silencieusement (CancelledError) et personne ne l'a vu pendant ~3
semaines, faute d'endpoint d'état. Ce health check expose l'état vivant du
worker + de la file SANS dépendre des logs, et renvoie 503 (actionnable /
alertable) quand `ML_ENABLED=true` mais que le worker ne tourne pas.
"""

from datetime import UTC, datetime, timedelta
from unittest.mock import MagicMock, patch
from uuid import uuid4

import pytest
import pytest_asyncio
from httpx import ASGITransport, AsyncClient

import app.main as main_module
from app.database import get_db
from app.main import app
from app.models.classification_queue import ClassificationQueue
from app.models.content import Content
from app.models.enums import ContentType, SourceType
from app.models.source import Source


def _source() -> Source:
    slug = uuid4()
    return Source(
        id=uuid4(),
        name="Classif Health",
        url=f"https://ch-{slug}.example.com",
        feed_url=f"https://ch-{slug}.example.com/feed.xml",
        type=SourceType.ARTICLE,
        theme="society",
        is_active=True,
        is_curated=False,
    )


def _content(source_id) -> Content:
    return Content(
        id=uuid4(),
        source_id=source_id,
        title="Article",
        url=f"https://ch.example.com/{uuid4()}",
        guid=str(uuid4()),
        published_at=datetime.now(UTC),
        content_type=ContentType.ARTICLE,
        theme=None,
    )


def _worker(running: bool) -> MagicMock:
    worker = MagicMock()
    worker.running = running
    return worker


@pytest_asyncio.fixture
async def health_client(db_session):
    async def _fake_db():
        yield db_session

    app.dependency_overrides[get_db] = _fake_db
    transport = ASGITransport(app=app)
    try:
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            yield ac, db_session
    finally:
        app.dependency_overrides.pop(get_db, None)


@pytest.mark.asyncio
async def test_worker_down_returns_503_with_full_payload(health_client):
    """ML_ENABLED=true mais worker mort → 503 actionnable + file remontée."""
    ac, db = health_client
    src = _source()
    db.add(src)
    await db.flush()
    for _ in range(2):
        c = _content(src.id)
        db.add(c)
        await db.flush()
        db.add(
            ClassificationQueue(
                id=uuid4(),
                content_id=c.id,
                status="pending",
                created_at=datetime.now(UTC) - timedelta(minutes=5),
            )
        )
    await db.commit()

    with (
        patch(
            "app.workers.classification_worker.get_worker",
            return_value=_worker(False),
        ),
        patch.object(main_module.settings, "ml_enabled", True),
    ):
        resp = await ac.get("/api/health/classification")

    assert resp.status_code == 503
    body = resp.json()
    assert body["status"] == "worker_down"
    assert body["worker_running"] is False
    assert body["ml_enabled"] is True
    assert body["pending"] == 2
    assert body["oldest_pending_age_s"] is not None
    assert body["oldest_pending_age_s"] >= 0
    # Aucun completed → dernier thème inconnu (le symptôme exact du 30/06).
    assert body["last_completed_at"] is None
    assert body["last_completed_age_s"] is None
    assert body["probe"] == "classification"


@pytest.mark.asyncio
async def test_worker_running_returns_ok_with_last_completed(health_client):
    """Worker vivant + un `processed_at` récent → 200 `ok`, âge calculé (no 500).

    Valide au passage la robustesse fuseau : `processed_at` revient tz-aware
    sous le harness (`timestamptz`) ; la soustraction ne doit pas lever.
    """
    ac, db = health_client
    src = _source()
    db.add(src)
    await db.flush()
    c = _content(src.id)
    db.add(c)
    await db.flush()
    db.add(
        ClassificationQueue(
            id=uuid4(),
            content_id=c.id,
            status="completed",
            processed_at=datetime.now(UTC) - timedelta(minutes=2),
        )
    )
    await db.commit()

    with (
        patch(
            "app.workers.classification_worker.get_worker",
            return_value=_worker(True),
        ),
        patch.object(main_module.settings, "ml_enabled", True),
    ):
        resp = await ac.get("/api/health/classification")

    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "ok"
    assert body["worker_running"] is True
    assert body["pending"] == 0
    assert body["last_completed_at"] is not None
    assert body["last_completed_age_s"] is not None
    assert body["last_completed_age_s"] >= 60


@pytest.mark.asyncio
async def test_ml_disabled_returns_200_disabled(health_client):
    """Service où le worker est légitimement off (ML_ENABLED=false) → 200/disabled."""
    ac, _db = health_client
    with (
        patch(
            "app.workers.classification_worker.get_worker",
            return_value=_worker(False),
        ),
        patch.object(main_module.settings, "ml_enabled", False),
    ):
        resp = await ac.get("/api/health/classification")

    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "disabled"
    assert body["worker_running"] is False
    assert body["ml_enabled"] is False
