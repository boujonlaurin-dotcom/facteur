"""Test la *logique* de migration 22a1_interest_state_favorites (Story 22.1).

On ne re-joue pas Alembic : on insère manuellement un état pré-migration
(doublons + weights/multipliers), puis on exécute le SQL data-fix de la
migration et on vérifie le résultat. La création du schéma elle-même est
couverte en bout-en-bout par `alembic upgrade head` (cf. branch Supabase de
test + verification end-to-end manuelle).
"""

from uuid import uuid4

import pytest
from sqlalchemy import text

from app.models.enums import InterestState, SourceType
from app.models.source import Source, UserSource
from app.models.user import UserInterest, UserProfile
from app.models.user_topic_profile import UserTopicProfile


@pytest.mark.asyncio
async def test_dedupe_keeps_max_weight_row(db_session):
    """Le DELETE de dedupe garde la row de plus grand weight pour chaque
    (user_id, interest_slug). En prod (audit 2026-05-16) : 39 lignes à
    supprimer, toutes des doublons à 2 occurrences. On drop la UNIQUE
    constraint pour reproduire l'état pré-migration où les doublons étaient
    physiquement possibles."""
    user_id = uuid4()
    db_session.add(UserProfile(user_id=user_id, onboarding_completed=True))
    await db_session.commit()

    await db_session.execute(
        text("ALTER TABLE user_interests DROP CONSTRAINT user_interests_user_slug_uniq")
    )
    await db_session.commit()

    db_session.add_all(
        [
            UserInterest(user_id=user_id, interest_slug="tech", weight=0.3),
            UserInterest(user_id=user_id, interest_slug="tech", weight=1.8),  # gagnant
            UserInterest(user_id=user_id, interest_slug="society", weight=1.0),
        ]
    )
    await db_session.commit()

    # SQL identique à upgrade() de 22a1_interest_state_favorites.py.
    await db_session.execute(
        text(
            """
            DELETE FROM user_interests
            WHERE id IN (
              SELECT id FROM (
                SELECT id, ROW_NUMBER() OVER (
                  PARTITION BY user_id, interest_slug
                  ORDER BY weight DESC, created_at DESC
                ) AS rn
                FROM user_interests
              ) t WHERE rn > 1
            )
            """
        )
    )
    await db_session.commit()

    rows = (
        (
            await db_session.execute(
                text(
                    "SELECT interest_slug, weight FROM user_interests "
                    "WHERE user_id = :uid ORDER BY interest_slug"
                ),
                {"uid": user_id},
            )
        )
        .all()
    )
    assert len(rows) == 2
    by_slug = {r[0]: r[1] for r in rows}
    assert by_slug["tech"] == 1.8
    assert by_slug["society"] == 1.0


@pytest.mark.asyncio
async def test_state_mapping_hides_low_weight_interests(db_session):
    """`UPDATE user_interests SET state='hidden' WHERE weight <= 0.5`."""
    user_id = uuid4()
    db_session.add(UserProfile(user_id=user_id, onboarding_completed=True))
    await db_session.flush()
    db_session.add_all(
        [
            UserInterest(user_id=user_id, interest_slug="a", weight=0.3),
            UserInterest(user_id=user_id, interest_slug="b", weight=0.5),  # frontier
            UserInterest(user_id=user_id, interest_slug="c", weight=0.51),
            UserInterest(user_id=user_id, interest_slug="d", weight=2.0),
        ]
    )
    await db_session.commit()

    await db_session.execute(
        text("UPDATE user_interests SET state = 'hidden' WHERE weight <= 0.5")
    )
    await db_session.commit()

    rows = (
        (
            await db_session.execute(
                text(
                    "SELECT interest_slug, state::text FROM user_interests "
                    "WHERE user_id = :uid ORDER BY interest_slug"
                ),
                {"uid": user_id},
            )
        )
        .all()
    )
    state_by_slug = dict(rows)
    assert state_by_slug["a"] == "hidden"
    assert state_by_slug["b"] == "hidden"
    assert state_by_slug["c"] == "followed"
    assert state_by_slug["d"] == "followed"


@pytest.mark.asyncio
async def test_state_mapping_hides_low_priority_sources(db_session):
    user_id = uuid4()
    db_session.add(UserProfile(user_id=user_id, onboarding_completed=True))

    sources = []
    for mult in (0.2, 1.0, 2.0):
        s = Source(
            id=uuid4(),
            name=f"Src {mult}",
            url=f"https://{uuid4()}.example.com",
            feed_url=f"https://{uuid4()}.example.com/feed.xml",
            type=SourceType.ARTICLE,
            theme="society",
            is_active=True,
            is_curated=False,
        )
        db_session.add(s)
        sources.append((s, mult))
    await db_session.flush()

    for s, mult in sources:
        db_session.add(
            UserSource(user_id=user_id, source_id=s.id, priority_multiplier=mult)
        )
    await db_session.commit()

    await db_session.execute(
        text(
            "UPDATE user_sources SET state = 'hidden' "
            "WHERE priority_multiplier = 0.2"
        )
    )
    await db_session.commit()

    rows = (
        (
            await db_session.execute(
                text(
                    "SELECT priority_multiplier, state::text FROM user_sources "
                    "WHERE user_id = :uid"
                ),
                {"uid": user_id},
            )
        )
        .all()
    )
    by_mult = dict(rows)
    assert by_mult[0.2] == "hidden"
    assert by_mult[1.0] == "followed"
    assert by_mult[2.0] == "followed"
