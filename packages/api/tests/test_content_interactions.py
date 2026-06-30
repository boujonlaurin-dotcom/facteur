import pytest
from unittest.mock import MagicMock, AsyncMock, patch
from uuid import uuid4
from datetime import datetime

from app.services.content_service import ContentService
from app.models.content import UserContentStatus


@pytest.mark.asyncio
async def test_set_save_status():
    session = AsyncMock()
    service = ContentService(session)

    user_id = uuid4()
    content_id = uuid4()

    # Mock result
    mock_status = UserContentStatus(
        user_id=user_id, content_id=content_id, is_saved=True
    )

    # We need to mock session.scalars(stmt).one()
    # scalars return a Result object
    mock_result = MagicMock()
    mock_result.one.return_value = mock_status
    session.scalars.return_value = mock_result

    with patch.object(service, "_adjust_subtopic_weights", new_callable=AsyncMock):
        result = await service.set_save_status(user_id, content_id, True)

    assert result.is_saved == True


# ---------------------------------------------------------------------------
# PR2 — _adjust_entity_affinity (boucle d'apprentissage entités, DB réelle)
# ---------------------------------------------------------------------------

import json as _json

from sqlalchemy import select as _select

from app.models.content import Content
from app.models.enums import ContentType
from app.models.learning import UserEntityAffinity, UserEntityPreference
from app.models.user import UserProfile


def _entity_json(name, type_="PERSON"):
    return _json.dumps({"name": name, "type": type_})


async def _seed_user_and_content(db_session, test_source, entities):
    """Crée un UserProfile (FK) + un Content avec `entities`. Renvoie les ids."""
    user_id = uuid4()
    db_session.add(UserProfile(user_id=user_id))
    content = Content(
        id=uuid4(),
        source_id=test_source.id,
        title="Article entités",
        url=f"https://example.com/ent-{uuid4()}",
        guid=f"ent-guid-{uuid4()}",
        published_at=datetime.utcnow(),
        content_type=ContentType.ARTICLE,
        entities=entities,
    )
    db_session.add(content)
    await db_session.commit()
    return user_id, content.id


async def _affinity_rows(db_session, user_id):
    rows = (
        (
            await db_session.execute(
                _select(UserEntityAffinity).where(UserEntityAffinity.user_id == user_id)
            )
        )
        .scalars()
        .all()
    )
    return {r.entity_canonical: r for r in rows}


@pytest.mark.asyncio
async def test_adjust_entity_affinity_parses_and_creates(db_session, test_source):
    """Parse JSON, crée 1 ligne/entité, affinity=1.0+delta, count=1."""
    user_id, content_id = await _seed_user_and_content(
        db_session,
        test_source,
        [_entity_json("Emmanuel Macron"), _entity_json("OpenAI", "ORG")],
    )
    service = ContentService(db_session)

    await service._adjust_entity_affinity(user_id, content_id, 0.15)
    await db_session.commit()

    rows = await _affinity_rows(db_session, user_id)
    assert set(rows) == {"emmanuel macron", "openai"}
    assert rows["emmanuel macron"].affinity == pytest.approx(1.15)
    assert rows["emmanuel macron"].interaction_count == 1


@pytest.mark.asyncio
async def test_adjust_entity_affinity_increments_count(db_session, test_source):
    """Deux signaux positifs cumulent l'affinité et incrémentent le count."""
    user_id, content_id = await _seed_user_and_content(
        db_session, test_source, [_entity_json("Emmanuel Macron")]
    )
    service = ContentService(db_session)

    await service._adjust_entity_affinity(user_id, content_id, 0.15)
    await service._adjust_entity_affinity(user_id, content_id, 0.15)
    await db_session.commit()

    rows = await _affinity_rows(db_session, user_id)
    assert rows["emmanuel macron"].affinity == pytest.approx(1.30)
    assert rows["emmanuel macron"].interaction_count == 2


@pytest.mark.asyncio
async def test_adjust_entity_affinity_caps_entities(db_session, test_source):
    """Au plus ENTITY_AFFINITY_MAX_ENTITIES entités apprises par article."""
    from app.services.recommendation.scoring_config import ScoringWeights

    user_id, content_id = await _seed_user_and_content(
        db_session, test_source, [_entity_json(f"Entité {i}") for i in range(8)]
    )
    service = ContentService(db_session)

    await service._adjust_entity_affinity(user_id, content_id, 0.15)
    await db_session.commit()

    rows = await _affinity_rows(db_session, user_id)
    assert len(rows) == ScoringWeights.ENTITY_AFFINITY_MAX_ENTITIES


@pytest.mark.asyncio
async def test_adjust_entity_affinity_skips_muted(db_session, test_source):
    """Une entité mutée n'est jamais récompensée."""
    user_id, content_id = await _seed_user_and_content(
        db_session,
        test_source,
        [_entity_json("Emmanuel Macron"), _entity_json("OpenAI", "ORG")],
    )
    db_session.add(
        UserEntityPreference(
            user_id=user_id, entity_canonical="openai", preference="mute"
        )
    )
    await db_session.commit()
    service = ContentService(db_session)

    await service._adjust_entity_affinity(user_id, content_id, 0.15)
    await db_session.commit()

    rows = await _affinity_rows(db_session, user_id)
    assert set(rows) == {"emmanuel macron"}


@pytest.mark.asyncio
async def test_adjust_entity_affinity_clamps_upper(db_session, test_source):
    """L'affinité est plafonnée à 3.0."""
    user_id, content_id = await _seed_user_and_content(
        db_session, test_source, [_entity_json("Emmanuel Macron")]
    )
    db_session.add(
        UserEntityAffinity(
            user_id=user_id,
            entity_canonical="emmanuel macron",
            affinity=2.95,
            interaction_count=10,
        )
    )
    await db_session.commit()
    service = ContentService(db_session)

    await service._adjust_entity_affinity(user_id, content_id, 0.15)
    await db_session.commit()

    rows = await _affinity_rows(db_session, user_id)
    assert rows["emmanuel macron"].affinity == pytest.approx(3.0)


@pytest.mark.asyncio
async def test_adjust_entity_affinity_negative_no_row_when_unknown(
    db_session, test_source
):
    """Un delta négatif sur une entité inconnue ne crée aucune ligne."""
    user_id, content_id = await _seed_user_and_content(
        db_session, test_source, [_entity_json("Emmanuel Macron")]
    )
    service = ContentService(db_session)

    await service._adjust_entity_affinity(user_id, content_id, -0.15)
    await db_session.commit()

    rows = await _affinity_rows(db_session, user_id)
    assert rows == {}


@pytest.mark.asyncio
async def test_adjust_entity_affinity_negative_clamps_lower(db_session, test_source):
    """Un signal négatif décrémente l'existant, plancher 0.1."""
    user_id, content_id = await _seed_user_and_content(
        db_session, test_source, [_entity_json("Emmanuel Macron")]
    )
    db_session.add(
        UserEntityAffinity(
            user_id=user_id,
            entity_canonical="emmanuel macron",
            affinity=0.2,
            interaction_count=3,
        )
    )
    await db_session.commit()
    service = ContentService(db_session)

    await service._adjust_entity_affinity(user_id, content_id, -0.15)
    await db_session.commit()

    rows = await _affinity_rows(db_session, user_id)
    assert rows["emmanuel macron"].affinity == pytest.approx(0.1)
