"""Tests du volume de publication 30 j exposé sur le catalogue (`articles_30d`).

Le recommander d'onboarding favorise les « sources productives » : le service
catalogue enrichit chaque `SourceResponse` curée avec le nombre d'articles
publiés sur 30 j, via un unique GROUP BY batché (jamais d'appel par source).

Couvre :
- `get_all_sources` : `articles_30d` peuplé pour les curées actives, fenêtre 30 j
  respectée (un article à 40 j exclu), 0 pour une curée sans contenu récent ;
- `get_curated_sources` : même enrichissement.
"""

from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.content import Content
from app.models.enums import ContentType, SourceType
from app.models.source import Source
from app.services.source_service import SourceService


def _curated_source(name: str) -> Source:
    return Source(
        id=uuid4(),
        name=name,
        url=f"https://{uuid4()}.example.com",
        feed_url=f"https://{uuid4()}.example.com/feed.xml",
        type=SourceType.ARTICLE,
        theme="society",
        is_active=True,
        is_curated=True,
    )


def _content(source_id, *, days_ago: int) -> Content:
    return Content(
        id=uuid4(),
        source_id=source_id,
        title="Article",
        url=f"https://example.com/{uuid4()}",
        guid=str(uuid4()),
        published_at=datetime.now(UTC) - timedelta(days=days_ago),
        content_type=ContentType.ARTICLE,
        theme="society",
    )


@pytest.mark.asyncio
async def test_get_all_sources_populates_articles_30d(db_session: AsyncSession):
    active = _curated_source("Active Source")
    quiet = _curated_source("Quiet Source")
    db_session.add_all([active, quiet])
    await db_session.flush()

    # 3 articles récents + 1 hors fenêtre (40 j) pour 'active' ; rien pour 'quiet'.
    for d in (0, 5, 20):
        db_session.add(_content(active.id, days_ago=d))
    db_session.add(_content(active.id, days_ago=40))
    await db_session.commit()

    catalog = await SourceService(db_session).get_all_sources(str(uuid4()))
    by_name = {s.name: s for s in catalog.curated}

    assert by_name["Active Source"].articles_30d == 3  # le 40 j est exclu
    assert by_name["Quiet Source"].articles_30d == 0


@pytest.mark.asyncio
async def test_get_curated_sources_populates_articles_30d(db_session: AsyncSession):
    src = _curated_source("Curated Source")
    db_session.add(src)
    await db_session.flush()
    for d in (1, 2):
        db_session.add(_content(src.id, days_ago=d))
    await db_session.commit()

    curated = await SourceService(db_session).get_curated_sources()
    match = next(s for s in curated if s.name == "Curated Source")
    assert match.articles_30d == 2
