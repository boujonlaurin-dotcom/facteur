"""Test logique de la migration 23a4_restore_ct_favorites.

La migration 23a3 a supprimé les favoris `custom_topic` mais a laissé la
signature `priority_multiplier=2.0` intacte sur les `user_topic_profiles`.
23a4 exploite cette signature pour rétablir le state `favorite` et insérer
les rows manquantes dans `user_favorite_interests`.

Les blocs SQL ci-dessous DOIVENT rester synchronisés avec
`alembic/versions/23a4_restore_ct_favorites.py`.
"""

from uuid import uuid4

import pytest
from sqlalchemy import text

from app.models.enums import InterestState
from app.models.user import UserProfile
from app.models.user_favorites import UserFavoriteInterest
from app.models.user_topic_profile import UserTopicProfile

RESTORE_FAVORITE_INTERESTS_SQL = """
WITH candidates AS (
    SELECT
        p.user_id,
        p.id AS custom_topic_id,
        p.created_at AS topic_created_at
    FROM user_topic_profiles p
    WHERE p.state = 'followed'
      AND p.priority_multiplier = 2.0
      AND NOT EXISTS (
          SELECT 1
          FROM user_favorite_interests fi
          WHERE fi.user_id = p.user_id
            AND fi.custom_topic_id = p.id
      )
),
current_max AS (
    SELECT user_id, COALESCE(MAX(position), -1) AS max_pos
    FROM user_favorite_interests
    GROUP BY user_id
),
positioned AS (
    SELECT
        c.user_id,
        c.custom_topic_id,
        COALESCE(cm.max_pos, -1)
          + ROW_NUMBER() OVER (PARTITION BY c.user_id ORDER BY c.topic_created_at) AS position
    FROM candidates c
    LEFT JOIN current_max cm ON cm.user_id = c.user_id
)
INSERT INTO user_favorite_interests (user_id, position, custom_topic_id)
SELECT user_id, position, custom_topic_id FROM positioned;
"""

PROMOTE_STATE_SQL = """
UPDATE user_topic_profiles
SET state = 'favorite'
WHERE state = 'followed' AND priority_multiplier = 2.0;
"""


async def _run_restore(db_session):
    await db_session.execute(text(RESTORE_FAVORITE_INTERESTS_SQL))
    await db_session.execute(text(PROMOTE_STATE_SQL))
    await db_session.commit()


@pytest.mark.asyncio
async def test_restore_promotes_followed_topic_with_multiplier_2(db_session):
    """Un sujet `followed + multiplier=2` est promu favori et inséré."""
    user_id = uuid4()
    db_session.add(UserProfile(user_id=user_id, onboarding_completed=True))
    topic = UserTopicProfile(
        user_id=user_id,
        topic_name="Plongée",
        slug_parent="sport",
        priority_multiplier=2.0,
        state=InterestState.FOLLOWED,
    )
    db_session.add(topic)
    await db_session.commit()

    await _run_restore(db_session)

    await db_session.refresh(topic)
    assert topic.state == InterestState.FAVORITE

    favs = (
        await db_session.execute(
            text(
                "SELECT position, custom_topic_id FROM user_favorite_interests "
                "WHERE user_id = :uid"
            ),
            {"uid": user_id},
        )
    ).all()
    assert favs == [(0, topic.id)]


@pytest.mark.asyncio
async def test_restore_ignores_followed_topic_with_multiplier_1(db_session):
    """Un sujet `followed + multiplier=1` (boost normal) n'est pas touché."""
    user_id = uuid4()
    db_session.add(UserProfile(user_id=user_id, onboarding_completed=True))
    topic = UserTopicProfile(
        user_id=user_id,
        topic_name="Cuisine",
        slug_parent="lifestyle",
        priority_multiplier=1.0,
        state=InterestState.FOLLOWED,
    )
    db_session.add(topic)
    await db_session.commit()

    await _run_restore(db_session)

    await db_session.refresh(topic)
    assert topic.state == InterestState.FOLLOWED

    count = (
        await db_session.execute(
            text(
                "SELECT COUNT(*) FROM user_favorite_interests WHERE user_id = :uid"
            ),
            {"uid": user_id},
        )
    ).scalar_one()
    assert count == 0


@pytest.mark.asyncio
async def test_restore_appends_after_existing_theme_favorites(db_session):
    """Si l'user a déjà des favoris (thèmes), les sujets restaurés prennent
    les positions suivantes (max+1, max+2, …)."""
    user_id = uuid4()
    db_session.add(UserProfile(user_id=user_id, onboarding_completed=True))
    topic = UserTopicProfile(
        user_id=user_id,
        topic_name="Tech",
        slug_parent="tech",
        priority_multiplier=2.0,
        state=InterestState.FOLLOWED,
    )
    db_session.add(topic)
    db_session.add_all(
        [
            UserFavoriteInterest(user_id=user_id, position=0, interest_slug="tech"),
            UserFavoriteInterest(
                user_id=user_id, position=1, interest_slug="science"
            ),
        ]
    )
    await db_session.commit()

    await _run_restore(db_session)

    favs = (
        await db_session.execute(
            text(
                "SELECT position, custom_topic_id, interest_slug "
                "FROM user_favorite_interests WHERE user_id = :uid ORDER BY position"
            ),
            {"uid": user_id},
        )
    ).all()
    assert favs == [
        (0, None, "tech"),
        (1, None, "science"),
        (2, topic.id, None),
    ]


@pytest.mark.asyncio
async def test_restore_is_idempotent(db_session):
    """Re-run la migration ne duplique pas les rows."""
    user_id = uuid4()
    db_session.add(UserProfile(user_id=user_id, onboarding_completed=True))
    topic = UserTopicProfile(
        user_id=user_id,
        topic_name="IA",
        slug_parent="tech",
        priority_multiplier=2.0,
        state=InterestState.FOLLOWED,
    )
    db_session.add(topic)
    await db_session.commit()

    await _run_restore(db_session)
    await _run_restore(db_session)

    favs = (
        await db_session.execute(
            text(
                "SELECT position, custom_topic_id FROM user_favorite_interests "
                "WHERE user_id = :uid"
            ),
            {"uid": user_id},
        )
    ).all()
    assert favs == [(0, topic.id)]


@pytest.mark.asyncio
async def test_restore_multiple_topics_ordered_by_created_at(db_session):
    """Plusieurs sujets restaurés → ordre par created_at ASC (premier favori = premier épinglé)."""
    from datetime import UTC, datetime, timedelta

    user_id = uuid4()
    db_session.add(UserProfile(user_id=user_id, onboarding_completed=True))

    now = datetime.now(UTC)
    topics = [
        UserTopicProfile(
            user_id=user_id,
            topic_name=f"Sujet {i}",
            slug_parent="tech",
            priority_multiplier=2.0,
            state=InterestState.FOLLOWED,
            created_at=now + timedelta(minutes=i),
        )
        for i in range(3)
    ]
    db_session.add_all(topics)
    await db_session.commit()

    await _run_restore(db_session)

    favs = (
        await db_session.execute(
            text(
                "SELECT position, custom_topic_id FROM user_favorite_interests "
                "WHERE user_id = :uid ORDER BY position"
            ),
            {"uid": user_id},
        )
    ).all()
    assert [f[0] for f in favs] == [0, 1, 2]
    assert [f[1] for f in favs] == [t.id for t in topics]
