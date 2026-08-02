"""Re-pondération des intérêts sur lecture — comportement C-1 (UPDATE-only).

Contexte historique (PYTHON-4P) : l'ancien code faisait un check-then-insert
puis un upsert `ON CONFLICT` pour éviter la race SEEN/CONSUMED.

C-1 (bug-curation-essentiel-personnalisation §3.1) va plus loin : une **lecture
est un signal passif** et ne doit plus **fabriquer** d'intérêt. Fabriquer une
ligne `state='followed'` sur le thème de la SOURCE empoisonnait la perso et
contredisait les `muted_themes`. `_adjust_interest_weight` fait donc désormais
un **UPDATE seul** (no-op si la ligne n'existe pas) : plus aucune création sur
lecture, la course d'insertion disparaît de fait (plus d'INSERT). La création
reste réservée aux signaux explicites (like/save/note).

NB : la fixture `db_session` isole chaque test dans une connexion unique +
savepoints (cf. conftest).
"""

from datetime import datetime
from uuid import uuid4

import pytest
from sqlalchemy import select

from app.models.content import Content
from app.models.enums import ContentType, InterestState
from app.models.user import UserInterest, UserProfile
from app.services.content_service import ContentService


async def _make_user(db_session):
    """Crée un UserProfile valide — la FK user_interests_user_id_fkey l'exige."""
    user_id = uuid4()
    db_session.add(UserProfile(user_id=user_id, display_name="Test User"))
    await db_session.commit()
    return user_id


async def _make_content(db_session, source, *, duration_seconds=None):
    content = Content(
        id=uuid4(),
        source_id=source.id,
        title="Article test",
        url=f"https://example.com/{uuid4()}",
        guid=str(uuid4()),
        published_at=datetime.utcnow(),
        content_type=ContentType.ARTICLE,
        duration_seconds=duration_seconds,
    )
    db_session.add(content)
    await db_session.commit()
    return content


@pytest.mark.asyncio
async def test_read_does_not_create_interest(db_session, test_source):
    """C-1 : une lecture sur un thème inconnu ne FABRIQUE plus d'intérêt."""
    service = ContentService(db_session)
    user_id = await _make_user(db_session)
    content = await _make_content(db_session, test_source)
    content_id = content.id
    theme = test_source.theme  # "society"

    await service._adjust_interest_weight(user_id, content_id, time_spent=None)
    await db_session.commit()

    db_session.expunge_all()
    row = await db_session.scalar(
        select(UserInterest).where(
            UserInterest.user_id == user_id,
            UserInterest.interest_slug == theme,
        )
    )
    assert row is None, "la lecture ne doit créer aucun UserInterest (C-1)"


@pytest.mark.asyncio
async def test_read_increments_existing_interest(db_session, test_source):
    """Une lecture RENFORCE un intérêt déjà déclaré (UPDATE), sans doublon."""
    service = ContentService(db_session)
    user_id = await _make_user(db_session)
    content = await _make_content(db_session, test_source)
    content_id = content.id
    theme = test_source.theme

    # Intérêt déclaré préexistant (ex. onboarding), weight 1.0.
    db_session.add(
        UserInterest(user_id=user_id, interest_slug=theme, weight=1.0)
    )
    await db_session.commit()

    await service._adjust_interest_weight(user_id, content_id, time_spent=None)
    await db_session.commit()

    db_session.expunge_all()
    rows = (
        await db_session.scalars(
            select(UserInterest).where(
                UserInterest.user_id == user_id,
                UserInterest.interest_slug == theme,
            )
        )
    ).all()
    assert len(rows) == 1
    # engagement_factor=1.0 (pas de time_spent), learning_rate=0.05
    assert rows[0].weight == pytest.approx(1.0 + 0.05)


@pytest.mark.asyncio
async def test_adjust_interest_weight_caps_at_3(db_session, test_source):
    """Le DO UPDATE préserve le cap métier à 3.0."""
    service = ContentService(db_session)
    user_id = await _make_user(db_session)
    content = await _make_content(db_session, test_source)
    theme = test_source.theme

    # Seed près du plafond.
    db_session.add(UserInterest(user_id=user_id, interest_slug=theme, weight=2.99))
    await db_session.commit()

    # Plusieurs incréments : le poids ne dépasse jamais 3.0.
    for _ in range(5):
        await service._adjust_interest_weight(user_id, content.id, time_spent=None)
    await db_session.commit()

    db_session.expunge_all()
    row = await db_session.scalar(
        select(UserInterest).where(
            UserInterest.user_id == user_id,
            UserInterest.interest_slug == theme,
        )
    )
    assert row.weight == pytest.approx(3.0)


@pytest.mark.asyncio
async def test_adjust_interest_weight_preserves_favorite_state(db_session, test_source):
    """Sur conflit, le state (ex. FAVORITE) n'est jamais écrasé."""
    service = ContentService(db_session)
    user_id = await _make_user(db_session)
    content = await _make_content(db_session, test_source)
    theme = test_source.theme

    db_session.add(
        UserInterest(
            user_id=user_id,
            interest_slug=theme,
            weight=1.5,
            state=InterestState.FAVORITE,
        )
    )
    await db_session.commit()

    await service._adjust_interest_weight(user_id, content.id, time_spent=None)
    await db_session.commit()

    db_session.expunge_all()
    row = await db_session.scalar(
        select(UserInterest).where(
            UserInterest.user_id == user_id,
            UserInterest.interest_slug == theme,
        )
    )
    assert row.state == InterestState.FAVORITE
    assert row.weight == pytest.approx(1.55)
