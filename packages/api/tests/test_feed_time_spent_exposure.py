"""Story 30.4 — le feed expose `time_spent_seconds` pour départager, côté carte,
« Ouvert » (< 5 s) de « Lu en partie ».

Pas de DB : on mocke la session et on inspecte l'hydratation du champ transient
+ la sérialisation `ContentResponse`.
"""

from datetime import datetime
from unittest.mock import AsyncMock
from uuid import uuid4

import pytest

from app.models.content import Content, UserContentStatus
from app.models.enums import ContentStatus, ContentType
from app.schemas.content import ContentResponse
from app.services.recommendation_service import RecommendationService


def _content(content_id) -> Content:
    return Content(id=content_id, source_id=uuid4())


def _response_kwargs() -> dict:
    return {
        "id": uuid4(),
        "title": "T",
        "url": "https://x",
        "thumbnail_url": None,
        "content_type": ContentType.ARTICLE,
        "duration_seconds": None,
        "published_at": datetime(2026, 7, 24, 8),
        "source": {
            "id": uuid4(),
            "name": "S",
            "logo_url": None,
            "type": "article",
            "theme": None,
        },
    }


@pytest.mark.asyncio
async def test_hydrate_user_status_sets_time_spent_seconds():
    user_id = uuid4()
    cid_low = uuid4()
    cid_high = uuid4()
    cid_none = uuid4()

    statuses = [
        UserContentStatus(
            user_id=user_id,
            content_id=cid_low,
            status=ContentStatus.CONSUMED,
            time_spent_seconds=2,
        ),
        UserContentStatus(
            user_id=user_id,
            content_id=cid_high,
            status=ContentStatus.CONSUMED,
            time_spent_seconds=42,
        ),
    ]

    session = AsyncMock()
    session.scalars.return_value = statuses

    items = [_content(cid_low), _content(cid_high), _content(cid_none)]
    service = RecommendationService(session)
    await service._hydrate_user_status(items, user_id)

    by_id = {c.id: c for c in items}
    # Valeur accumulée reflétée telle quelle…
    assert by_id[cid_low].time_spent_seconds == 2
    assert by_id[cid_high].time_spent_seconds == 42
    # …et défaut sûr à 0 quand aucun statut (item jamais ouvert).
    assert by_id[cid_none].time_spent_seconds == 0


def test_content_response_serializes_time_spent_seconds():
    dumped = ContentResponse(**_response_kwargs(), time_spent_seconds=3).model_dump()
    assert dumped["time_spent_seconds"] == 3


def test_content_response_defaults_time_spent_to_zero():
    # Champ absent → défaut 0 (jamais None : l'UI lit un int).
    dumped = ContentResponse(**_response_kwargs()).model_dump()
    assert dumped["time_spent_seconds"] == 0
