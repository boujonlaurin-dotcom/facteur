"""Tests for DigestService._get_emergency_candidates in serein mode.

Régression : le fallback d'urgence on-demand utilisait `apply_serein_filter`
(is_serene) au lieu de `apply_good_news_filter` (is_good_news). Quand la classif
est à l'arrêt (tout le frais is_good_news=NULL, is_serene=NULL), il laissait
passer du contenu quelconque non-anxiogène (transactions NBA…) dans le digest
« Bonnes nouvelles du jour ». Ces tests verrouillent le hard-filter is_good_news
et l'absence de repli élargi 30 j en serein.
"""

from datetime import datetime
from uuid import uuid4

import pytest

from app.models.content import Content
from app.models.enums import ContentType, InterestState, SourceType
from app.models.source import Source, UserSource
from app.services.digest_service import DigestService


async def _make_source(db_session, *, theme="tech", is_curated=True):
    src = Source(
        id=uuid4(),
        name="Basket USA",
        url="https://basketusa.example.com",
        feed_url=f"https://basketusa.example.com/feed-{uuid4()}.xml",
        type=SourceType.ARTICLE,
        theme=theme,
        is_active=True,
        is_curated=is_curated,
    )
    db_session.add(src)
    await db_session.commit()
    return src


async def _make_content(db_session, source, title, *, is_good_news, is_serene=None):
    content = Content(
        id=uuid4(),
        source_id=source.id,
        title=title,
        url=f"https://example.com/{uuid4()}",
        guid=f"guid-{uuid4()}",
        published_at=datetime.utcnow(),
        content_type=ContentType.ARTICLE,
        is_good_news=is_good_news,
        is_serene=is_serene,
    )
    db_session.add(content)
    await db_session.commit()
    return content


@pytest.mark.asyncio
async def test_serein_emergency_keeps_only_good_news(db_session):
    """En serein, seul is_good_news=True survit ; NULL (non classifié) et False exclus."""
    source = await _make_source(db_session)

    good = await _make_content(
        db_session,
        source,
        "Une avancée concrète pour l'accès à l'eau",
        is_good_news=True,
    )
    # Transaction NBA fraîche, non classifiée (worker classif à l'arrêt).
    await _make_content(
        db_session, source, "Ja Morant transféré aux Blazers !", is_good_news=None
    )
    await _make_content(db_session, source, "Article anxiogène", is_good_news=False)

    service = DigestService(db_session)
    items = await service._get_emergency_candidates(
        user_id=uuid4(), limit=5, is_serene=True
    )

    returned_ids = {item.content.id for item in items}
    assert returned_ids == {good.id}


@pytest.mark.asyncio
async def test_serein_emergency_empty_when_no_good_news(db_session):
    """Aucun is_good_news=True → digest vide (fail-closed), pas de repli 30 j."""
    source = await _make_source(db_session)
    await _make_content(
        db_session, source, "Ja Morant transféré aux Blazers !", is_good_news=None
    )

    service = DigestService(db_session)
    items = await service._get_emergency_candidates(
        user_id=uuid4(), limit=5, is_serene=True
    )

    assert items == []


@pytest.mark.asyncio
async def test_serein_emergency_followed_source_not_bypassed(db_session):
    """Une source SUIVIE ne contourne pas le gate is_good_news en serein."""
    source = await _make_source(db_session, is_curated=False)
    user_id = uuid4()
    db_session.add(
        UserSource(user_id=user_id, source_id=source.id, state=InterestState.FOLLOWED)
    )
    await _make_content(db_session, source, "Rumeur NBA du jour", is_good_news=None)
    await db_session.commit()

    service = DigestService(db_session)
    items = await service._get_emergency_candidates(
        user_id=user_id, limit=5, is_serene=True
    )

    assert items == []


@pytest.mark.asyncio
async def test_non_serein_emergency_unaffected(db_session):
    """Mode non-serein : le fallback reste permissif (pas de gate is_good_news)."""
    source = await _make_source(db_session)
    await _make_content(db_session, source, "Actu tech du jour", is_good_news=None)

    service = DigestService(db_session)
    items = await service._get_emergency_candidates(
        user_id=uuid4(), limit=5, is_serene=False
    )

    assert len(items) == 1
