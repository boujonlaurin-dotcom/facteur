"""Test la *logique* de la migration cq01_subtopics_uniq_muted (C-1).

Comme `test_interest_state_migration.py`, on ne re-joue pas Alembic : on insère
un état pré-migration puis on exécute les blocs SQL data-fix de la migration et
on vérifie le résultat. La création du schéma (contrainte + index) est couverte
en bout-en-bout par `alembic upgrade head`.

Les constantes SQL ci-dessous DOIVENT rester synchronisées avec
`alembic/versions/cq01_subtopics_uniq_muted.py` (le dossier `tests/alembic/`
shadow le package `alembic` → on ne peut pas importer le module migration).
"""

from uuid import uuid4

import pytest
from sqlalchemy import text

from app.models.user import UserInterest, UserProfile, UserSubtopic
from app.models.user_personalization import UserPersonalization

# --- COPIE de alembic/versions/cq01_subtopics_uniq_muted.py ---
DEDUP_SUBTOPICS_SQL = """
DELETE FROM user_subtopics
WHERE id IN (
  SELECT id FROM (
    SELECT id, ROW_NUMBER() OVER (
      PARTITION BY user_id, topic_slug
      ORDER BY weight DESC, created_at DESC
    ) AS rn
    FROM user_subtopics
  ) t WHERE rn > 1
)
"""

DELETE_MUTED_INTERESTS_SQL = """
DELETE FROM user_interests ui
USING user_personalization up
WHERE up.user_id = ui.user_id
  AND ui.interest_slug = ANY(COALESCE(up.muted_themes, '{}'))
"""


@pytest.mark.asyncio
async def test_dedupe_keeps_max_weight_subtopic(db_session):
    """Le dédup garde la ligne de plus grand weight par (user_id, topic_slug)."""
    user_id = uuid4()
    db_session.add(UserProfile(user_id=user_id, onboarding_completed=True))
    await db_session.commit()

    # Reproduit l'état pré-migration : la contrainte d'unicité n'existait pas.
    await db_session.execute(
        text(
            "ALTER TABLE user_subtopics "
            "DROP CONSTRAINT uq_user_subtopics_user_topic"
        )
    )
    await db_session.commit()

    db_session.add_all(
        [
            UserSubtopic(user_id=user_id, topic_slug="ai", weight=0.3),
            UserSubtopic(user_id=user_id, topic_slug="ai", weight=1.8),  # gagnant
            UserSubtopic(user_id=user_id, topic_slug="crypto", weight=1.0),
        ]
    )
    await db_session.commit()

    await db_session.execute(text(DEDUP_SUBTOPICS_SQL))
    await db_session.commit()

    rows = (
        await db_session.execute(
            text(
                "SELECT topic_slug, weight FROM user_subtopics "
                "WHERE user_id = :uid ORDER BY topic_slug"
            ),
            {"uid": user_id},
        )
    ).all()
    assert len(rows) == 2
    by_slug = {r[0]: r[1] for r in rows}
    assert by_slug["ai"] == 1.8
    assert by_slug["crypto"] == 1.0

    # Idempotence : 2ᵉ passage ne supprime plus rien.
    result = await db_session.execute(text(DEDUP_SUBTOPICS_SQL))
    await db_session.commit()
    assert result.rowcount == 0


@pytest.mark.asyncio
async def test_delete_muted_interests_removes_only_muted(db_session):
    """Le DELETE retire les intérêts sur un thème muté, garde les autres."""
    user_id = uuid4()
    db_session.add(UserProfile(user_id=user_id, onboarding_completed=True))
    await db_session.commit()

    db_session.add(
        UserPersonalization(user_id=user_id, muted_themes=["tech", "sport"])
    )
    db_session.add_all(
        [
            UserInterest(user_id=user_id, interest_slug="tech", weight=1.05),
            UserInterest(user_id=user_id, interest_slug="politics", weight=1.2),
        ]
    )
    await db_session.commit()

    result = await db_session.execute(text(DELETE_MUTED_INTERESTS_SQL))
    await db_session.commit()
    assert result.rowcount == 1  # seul "tech" (muté) supprimé

    rows = (
        await db_session.execute(
            text(
                "SELECT interest_slug FROM user_interests "
                "WHERE user_id = :uid ORDER BY interest_slug"
            ),
            {"uid": user_id},
        )
    ).all()
    assert [r[0] for r in rows] == ["politics"]

    # Idempotence : 2ᵉ passage = 0 ligne supprimée.
    result = await db_session.execute(text(DELETE_MUTED_INTERESTS_SQL))
    await db_session.commit()
    assert result.rowcount == 0


@pytest.mark.asyncio
async def test_delete_muted_keeps_redeclared_theme(db_session):
    """Un thème muté PUIS re-déclaré (retiré de muted_themes) n'est pas supprimé."""
    user_id = uuid4()
    db_session.add(UserProfile(user_id=user_id, onboarding_completed=True))
    await db_session.commit()

    # L'utilisateur a re-déclaré "tech" → il n'est plus dans muted_themes.
    db_session.add(UserPersonalization(user_id=user_id, muted_themes=["sport"]))
    db_session.add(
        UserInterest(user_id=user_id, interest_slug="tech", weight=1.3)
    )
    await db_session.commit()

    result = await db_session.execute(text(DELETE_MUTED_INTERESTS_SQL))
    await db_session.commit()
    assert result.rowcount == 0

    row = await db_session.scalar(
        text(
            "SELECT interest_slug FROM user_interests WHERE user_id = :uid"
        ),
        {"uid": user_id},
    )
    assert row == "tech"


@pytest.mark.asyncio
async def test_delete_muted_noop_when_no_mutes(db_session):
    """Aucun mute (muted_themes vide) → aucun intérêt supprimé."""
    user_id = uuid4()
    db_session.add(UserProfile(user_id=user_id, onboarding_completed=True))
    await db_session.commit()
    db_session.add(UserPersonalization(user_id=user_id, muted_themes=[]))
    db_session.add(
        UserInterest(user_id=user_id, interest_slug="tech", weight=1.1)
    )
    await db_session.commit()

    result = await db_session.execute(text(DELETE_MUTED_INTERESTS_SQL))
    await db_session.commit()
    assert result.rowcount == 0
