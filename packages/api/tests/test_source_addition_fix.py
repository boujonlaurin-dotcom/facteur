"""Test du correctif ajout de source (prod 500 + isolation).

Vérifie que add_custom_source ne lève pas (ex. NameError logger)
et que l'idempotence fonctionne. Aucune config Flutter ni appel réseau.

Commande one-liner (depuis la racine du repo) :
  cd packages/api && python -m pytest tests/test_source_addition_fix.py -v

Sans DB (vérifier uniquement que le fix logger est présent) :
  cd packages/api && python -m pytest tests/test_source_addition_fix.py -v -k "has_logger"
"""

import pytest


def test_source_service_has_logger():
    """Vérifie que le correctif (logger défini) est présent — pas de NameError en prod."""
    from app.services import source_service

    assert hasattr(source_service, "logger")
    assert source_service.logger is not None


from unittest.mock import AsyncMock, patch
from uuid import uuid4

from httpx import ASGITransport, AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.dependencies import get_current_user_id
from app.main import app
from app.models.enums import InterestState, SourceType
from app.models.source import Source, UserSource
from app.models.user import UserProfile
from app.models.user_favorites import UserFavoriteSource
from app.schemas.source import SourceDetectResponse, SourceResponse
from app.services.source_service import SourceService


@pytest.fixture
def fake_detection():
    """Réponse de détection fictive (pas d'appel RSS)."""
    return SourceDetectResponse(
        detected_type=SourceType.ARTICLE,
        feed_url="https://example.com/test-feed.xml",
        name="Test Source",
        description=None,
        logo_url=None,
        theme="society",
        preview={"item_count": 1, "latest_title": "Test"},
    )


@pytest.mark.asyncio
async def test_add_custom_source_no_500(db_session: AsyncSession, fake_detection):
    """
    Vérifie que add_custom_source s'exécute sans 500 (ex. logger défini).
    Mock detect + create_task pour éviter réseau et sync.
    """
    user_id = str(uuid4())

    with patch.object(
        SourceService,
        "detect_source",
        new_callable=AsyncMock,
        return_value=fake_detection,
    ):
        service = SourceService(db_session)
        result = await service.add_custom_source(
            user_id, "https://example.com/feed", "Test Name"
        )

    assert result is not None
    assert result.name == "Test Name"
    assert result.id is not None
    assert result.is_custom is True


@pytest.mark.asyncio
async def test_add_custom_source_idempotent(db_session: AsyncSession, fake_detection):
    """Deux appels pour la même URL + même user : pas de doublon UserSource."""
    user_id = str(uuid4())

    with patch.object(
        SourceService,
        "detect_source",
        new_callable=AsyncMock,
        return_value=fake_detection,
    ):
        service = SourceService(db_session)
        r1 = await service.add_custom_source(
            user_id, "https://example.com/feed", "Test"
        )
        r2 = await service.add_custom_source(
            user_id, "https://example.com/feed", "Test"
        )

    assert r1.id == r2.id
    # Un seul lien user_sources pour ce (user_id, source_id)
    from uuid import UUID

    result = await db_session.execute(
        select(UserSource).where(
            UserSource.user_id == UUID(user_id),
            UserSource.source_id == r1.id,
        )
    )
    rows = result.scalars().all()
    assert len(rows) == 1


async def _fake_user():
    return str(uuid4())


class _DummyDB:
    async def commit(self):
        return None


async def _fake_db():
    yield _DummyDB()


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "payload",
    [
        {"url": "http://127.0.0.1/feed"},
        {"url": "localhost.localdomain"},
    ],
)
async def test_detect_route_rejects_private_internal_url(payload):
    app.dependency_overrides[get_current_user_id] = _fake_user
    app.dependency_overrides[get_db] = _fake_db
    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            with patch(
                "app.routers.sources._log_failed_source_attempt",
                new_callable=AsyncMock,
            ):
                resp = await ac.post("/api/sources/detect", json=payload)
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)
        app.dependency_overrides.pop(get_db, None)

    assert resp.status_code == 400


@pytest.mark.asyncio
async def test_custom_route_rejects_private_internal_url():
    app.dependency_overrides[get_current_user_id] = _fake_user
    app.dependency_overrides[get_db] = _fake_db
    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            with patch(
                "app.routers.sources._log_failed_source_attempt",
                new_callable=AsyncMock,
            ):
                resp = await ac.post(
                    "/api/sources/custom", json={"url": "http://127.0.0.1/feed"}
                )
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)
        app.dependency_overrides.pop(get_db, None)

    assert resp.status_code == 400


@pytest.mark.asyncio
@pytest.mark.parametrize("url", ["https://www.example.com/feed", "vert.eco"])
async def test_detect_route_public_url_success_mocked(url, fake_detection):
    app.dependency_overrides[get_current_user_id] = _fake_user
    app.dependency_overrides[get_db] = _fake_db
    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            with patch.object(
                SourceService,
                "detect_source",
                new_callable=AsyncMock,
                return_value=fake_detection,
            ):
                resp = await ac.post("/api/sources/detect", json={"url": url})
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)
        app.dependency_overrides.pop(get_db, None)

    assert resp.status_code == 200
    assert resp.json()["feed_url"] == fake_detection.feed_url


@pytest.mark.asyncio
async def test_custom_route_public_url_success_mocked():
    response = SourceResponse(
        id=uuid4(),
        name="Vert",
        url="https://vert.eco",
        type=SourceType.ARTICLE,
        theme="environment",
        description=None,
        logo_url=None,
        is_curated=False,
        is_custom=True,
        is_trusted=True,
        content_count=0,
    )

    app.dependency_overrides[get_current_user_id] = _fake_user
    app.dependency_overrides[get_db] = _fake_db
    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as ac:
            with patch.object(
                SourceService,
                "add_custom_source",
                new_callable=AsyncMock,
                return_value=response,
            ):
                resp = await ac.post(
                    "/api/sources/custom", json={"url": "https://vert.eco"}
                )
    finally:
        app.dependency_overrides.pop(get_current_user_id, None)
        app.dependency_overrides.pop(get_db, None)

    assert resp.status_code == 200
    assert resp.json()["url"] == "https://vert.eco"


@pytest.mark.asyncio
async def test_legacy_trust_source_forces_existing_row_followed(
    db_session: AsyncSession,
):
    user_id = uuid4()
    source = Source(
        id=uuid4(),
        name="Existing Source",
        url="https://existing.example.com",
        feed_url="https://existing.example.com/feed.xml",
        type=SourceType.ARTICLE,
        theme="tech",
        is_active=True,
        is_curated=True,
    )
    db_session.add(source)
    db_session.add(UserProfile(user_id=user_id))
    db_session.add(
        UserSource(
            user_id=user_id,
            source_id=source.id,
            state=InterestState.HIDDEN,
        )
    )
    db_session.add(UserFavoriteSource(user_id=user_id, source_id=source.id, position=0))
    await db_session.commit()

    assert await SourceService(db_session).trust_source(str(user_id), str(source.id))
    await db_session.commit()

    user_source = await db_session.scalar(
        select(UserSource).where(
            UserSource.user_id == user_id,
            UserSource.source_id == source.id,
        )
    )
    favorite = await db_session.scalar(
        select(UserFavoriteSource).where(
            UserFavoriteSource.user_id == user_id,
            UserFavoriteSource.source_id == source.id,
        )
    )
    assert user_source is not None
    assert user_source.state == InterestState.FOLLOWED
    assert favorite is None
