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

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.enums import InterestState, SourceType
from app.models.source import Source, UserSource
from app.models.user_favorites import UserFavoriteSource
from app.schemas.source import SourceDetectResponse
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
