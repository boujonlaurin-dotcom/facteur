"""Re-pondération des sous-thèmes — comportement C-1 (`allow_create`).

Calqué sur `test_interest_weight_concurrency.py`. C-1
(bug-curation-essentiel-personnalisation §3.1) : une lecture (signal passif) ne
FABRIQUE plus de ligne `user_subtopics` — seuls les signaux **explicites**
(like/save/note, `allow_create=True`) peuvent en créer une. L'upsert Postgres
(`ON CONFLICT (user_id, topic_slug)` → `uq_user_subtopics_user_topic`) borne le
poids [0.1, 3.0].
"""

from datetime import datetime
from uuid import uuid4

import pytest
from sqlalchemy import select

from app.models.content import Content
from app.models.enums import ContentType
from app.models.user import UserProfile, UserSubtopic
from app.services.content_service import ContentService
from app.services.recommendation.scoring_config import ScoringWeights


async def _make_user(db_session):
    user_id = uuid4()
    db_session.add(UserProfile(user_id=user_id, display_name="Test User"))
    await db_session.commit()
    return user_id


async def _make_content(db_session, source, *, topics):
    content = Content(
        id=uuid4(),
        source_id=source.id,
        title="Article test",
        url=f"https://example.com/{uuid4()}",
        guid=str(uuid4()),
        published_at=datetime.utcnow(),
        content_type=ContentType.ARTICLE,
        topics=topics,
    )
    db_session.add(content)
    await db_session.commit()
    return content


@pytest.mark.asyncio
async def test_read_does_not_create_subtopic(db_session, test_source):
    """C-1 : une lecture sur un topic inconnu ne crée AUCUN user_subtopics."""
    service = ContentService(db_session)
    user_id = await _make_user(db_session)
    content = await _make_content(db_session, test_source, topics=["ai"])
    content_id = content.id

    # Lecture : allow_create par défaut False.
    await service._adjust_subtopic_weights(
        user_id, content_id, ScoringWeights.READ_TOPIC_BOOST
    )
    await db_session.commit()

    db_session.expunge_all()
    row = await db_session.scalar(
        select(UserSubtopic).where(
            UserSubtopic.user_id == user_id,
            UserSubtopic.topic_slug == "ai",
        )
    )
    assert row is None, "la lecture ne doit créer aucun sous-thème (C-1)"


@pytest.mark.asyncio
async def test_like_creates_subtopic(db_session, test_source):
    """Un like (signal explicite, allow_create=True) crée le sous-thème."""
    service = ContentService(db_session)
    user_id = await _make_user(db_session)
    content = await _make_content(db_session, test_source, topics=["ai"])
    content_id = content.id

    await service._adjust_subtopic_weights(
        user_id, content_id, ScoringWeights.LIKE_TOPIC_BOOST, allow_create=True
    )
    await db_session.commit()

    db_session.expunge_all()
    row = await db_session.scalar(
        select(UserSubtopic).where(
            UserSubtopic.user_id == user_id,
            UserSubtopic.topic_slug == "ai",
        )
    )
    assert row is not None
    assert row.weight == pytest.approx(1.0 + ScoringWeights.LIKE_TOPIC_BOOST)


@pytest.mark.asyncio
async def test_read_increments_existing_subtopic(db_session, test_source):
    """Une lecture RENFORCE un sous-thème existant (UPDATE), sans doublon."""
    service = ContentService(db_session)
    user_id = await _make_user(db_session)
    content = await _make_content(db_session, test_source, topics=["ai"])
    content_id = content.id

    db_session.add(UserSubtopic(user_id=user_id, topic_slug="ai", weight=1.0))
    await db_session.commit()

    await service._adjust_subtopic_weights(
        user_id, content_id, ScoringWeights.READ_TOPIC_BOOST
    )
    await db_session.commit()

    db_session.expunge_all()
    rows = (
        await db_session.scalars(
            select(UserSubtopic).where(
                UserSubtopic.user_id == user_id,
                UserSubtopic.topic_slug == "ai",
            )
        )
    ).all()
    assert len(rows) == 1
    assert rows[0].weight == pytest.approx(1.0 + ScoringWeights.READ_TOPIC_BOOST)


@pytest.mark.asyncio
async def test_upsert_caps_at_3(db_session, test_source):
    """Le DO UPDATE de l'upsert préserve le cap métier à 3.0."""
    service = ContentService(db_session)
    user_id = await _make_user(db_session)
    content = await _make_content(db_session, test_source, topics=["ai"])

    db_session.add(UserSubtopic(user_id=user_id, topic_slug="ai", weight=2.95))
    await db_session.commit()

    for _ in range(5):
        await service._adjust_subtopic_weights(
            user_id,
            content.id,
            ScoringWeights.LIKE_TOPIC_BOOST,
            allow_create=True,
        )
    await db_session.commit()

    db_session.expunge_all()
    row = await db_session.scalar(
        select(UserSubtopic).where(
            UserSubtopic.user_id == user_id,
            UserSubtopic.topic_slug == "ai",
        )
    )
    assert row.weight == pytest.approx(3.0)


@pytest.mark.asyncio
async def test_negative_delta_clamps_at_floor(db_session, test_source):
    """Un signal négatif (dismiss) borne le poids à 0.1 sans créer de ligne."""
    service = ContentService(db_session)
    user_id = await _make_user(db_session)
    content = await _make_content(db_session, test_source, topics=["ai"])

    db_session.add(UserSubtopic(user_id=user_id, topic_slug="ai", weight=0.15))
    await db_session.commit()

    # DISMISS_TOPIC_PENALTY = -0.15 → 0.15 - 0.15 = 0.0 → clamp plancher 0.1.
    await service._adjust_subtopic_weights(
        user_id, content.id, ScoringWeights.DISMISS_TOPIC_PENALTY
    )
    await db_session.commit()

    db_session.expunge_all()
    row = await db_session.scalar(
        select(UserSubtopic).where(
            UserSubtopic.user_id == user_id,
            UserSubtopic.topic_slug == "ai",
        )
    )
    assert row.weight == pytest.approx(0.1)
