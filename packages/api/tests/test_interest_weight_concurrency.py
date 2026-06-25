"""Régression Sentry PYTHON-4P — race condition user_interests_user_slug_uniq.

L'ancien code de re-pondération des intérêts faisait un check-then-insert
(SELECT UserInterest ; si absent → add()). Sous concurrence (SEEN au scroll +
CONSUMED au retour WebView quasi-simultanés pour le même thème), les deux
requêtes voyaient "absent" et inséraient → IntegrityError sur
user_interests_user_slug_uniq → 500, et le commit de lecture était perdu.

Le fix remplace l'insertion par un upsert Postgres atomique
(INSERT ... ON CONFLICT (user_id, interest_slug) DO UPDATE). La requête
"perdante" d'une course emprunte la branche DO UPDATE — c'est exactement ce
qu'exerce ici un second appel séquentiel sur le même (user, thème).

NB : la fixture `db_session` isole chaque test dans une connexion unique +
savepoints (cf. conftest), donc une vraie concurrence 2-connexions n'est pas
reproductible ici ; on valide le chemin ON CONFLICT de façon déterministe.
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
async def test_adjust_interest_weight_creates_then_increments(db_session, test_source):
    """1er appel crée l'intérêt (1.0 + boost, FOLLOWED) ; 2e appel incrémente."""
    service = ContentService(db_session)
    user_id = await _make_user(db_session)
    content = await _make_content(db_session, test_source)
    content_id = content.id  # capturé avant expunge_all (évite un reload sync)
    theme = test_source.theme  # "society"

    # 1er appel : création
    await service._adjust_interest_weight(user_id, content_id, time_spent=None)
    await db_session.commit()

    db_session.expunge_all()  # l'upsert Core bypass l'ORM → vider l'identity map
    row = await db_session.scalar(
        select(UserInterest).where(
            UserInterest.user_id == user_id,
            UserInterest.interest_slug == theme,
        )
    )
    assert row is not None
    # engagement_factor=1.0 (pas de time_spent), learning_rate=0.05
    assert row.weight == pytest.approx(1.0 + 0.05)
    assert row.state == InterestState.FOLLOWED

    # 2e appel : branche ON CONFLICT DO UPDATE → incrément, une seule ligne
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
    assert len(rows) == 1, "pas de doublon : la contrainte unique tient"
    assert rows[0].weight == pytest.approx(1.0 + 0.05 + 0.05)


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
