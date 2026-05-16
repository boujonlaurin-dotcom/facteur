"""Test la *logique* de migration 22a1_interest_state_favorites (Story 22.1).

On ne re-joue pas Alembic : on insère manuellement un état pré-migration
(doublons + weights/multipliers), puis on exécute le SQL data-fix de la
migration et on vérifie le résultat. La création du schéma elle-même est
couverte en bout-en-bout par `alembic upgrade head` (cf. branch Supabase de
test + verification end-to-end manuelle).

Les blocs SQL ci-dessous DOIVENT rester synchronisés avec
`alembic/versions/22a1_interest_state_favorites.py` (le folder de tests
`tests/alembic/` shadow le package `alembic` à l'import → impossible
d'importer le module migration sans casser `from alembic import op`).
"""

from uuid import uuid4

import pytest
from sqlalchemy import text

from app.models.enums import InterestState, SourceType
from app.models.source import Source, UserSource
from app.models.user import UserInterest, UserProfile
from app.models.user_topic_profile import UserTopicProfile

# --- COPIE de alembic/versions/22a1_interest_state_favorites.py ---
# (cf. avertissement dans la docstring du module).
BACKFILL_FAVORITES_SQL = """
WITH
custom_favs AS (
    SELECT
        user_id,
        id AS custom_topic_id,
        ROW_NUMBER() OVER (
            PARTITION BY user_id
            ORDER BY priority_multiplier DESC, created_at DESC
        ) - 1 AS position
    FROM user_topic_profiles
    WHERE priority_multiplier = 2.0
),
custom_favs_capped AS (
    SELECT user_id, custom_topic_id, position
    FROM custom_favs
    WHERE position < 3
),
user_custom_counts AS (
    SELECT user_id, COUNT(*) AS cnt FROM custom_favs_capped GROUP BY user_id
),
theme_candidates AS (
    SELECT
        ui.user_id,
        ui.interest_slug,
        ROW_NUMBER() OVER (
            PARTITION BY ui.user_id
            ORDER BY ui.weight DESC, ui.created_at DESC
        ) - 1 AS rn
    FROM user_interests ui
    WHERE ui.state != 'hidden'
),
theme_favs AS (
    SELECT
        tc.user_id,
        tc.interest_slug,
        tc.rn + COALESCE(ucc.cnt, 0) AS position
    FROM theme_candidates tc
    LEFT JOIN user_custom_counts ucc ON ucc.user_id = tc.user_id
    WHERE tc.rn + COALESCE(ucc.cnt, 0) < 3
      AND tc.rn < (2 - COALESCE(ucc.cnt, 0))
),
all_users AS (
    SELECT DISTINCT user_id FROM user_profiles
),
total_so_far AS (
    SELECT user_id, SUM(cnt) AS total FROM (
        SELECT user_id, COUNT(*) AS cnt FROM custom_favs_capped GROUP BY user_id
        UNION ALL
        SELECT user_id, COUNT(*) AS cnt FROM theme_favs GROUP BY user_id
    ) s GROUP BY user_id
),
fallback_themes AS (
    SELECT
        au.user_id,
        s.interest_slug,
        (COALESCE(ts.total, 0) + s.idx) AS position
    FROM all_users au
    LEFT JOIN total_so_far ts ON ts.user_id = au.user_id
    CROSS JOIN LATERAL (
        VALUES ('tech', 0), ('science', 1)
    ) AS s(interest_slug, idx)
    WHERE COALESCE(ts.total, 0) < 2
      AND s.idx < (2 - COALESCE(ts.total, 0))
)
INSERT INTO user_favorite_interests (user_id, position, custom_topic_id, interest_slug)
SELECT user_id, position, custom_topic_id, NULL FROM custom_favs_capped
UNION ALL
SELECT user_id, position, NULL, interest_slug FROM theme_favs
UNION ALL
SELECT user_id, position, NULL, interest_slug FROM fallback_themes
ON CONFLICT (user_id, position) DO NOTHING
"""

SYNC_STATE_FAVORITE_INTERESTS_SQL = """
UPDATE user_interests ui SET state = 'favorite'
WHERE EXISTS (
    SELECT 1 FROM user_favorite_interests ufi
    WHERE ufi.user_id = ui.user_id
      AND ufi.interest_slug = ui.interest_slug
)
"""

SYNC_STATE_FAVORITE_TOPICS_SQL = """
UPDATE user_topic_profiles utp SET state = 'favorite'
WHERE EXISTS (
    SELECT 1 FROM user_favorite_interests ufi
    WHERE ufi.user_id = utp.user_id
      AND ufi.custom_topic_id = utp.id
)
"""

INSERT_FALLBACK_USER_INTERESTS_SQL = """
INSERT INTO user_interests (id, user_id, interest_slug, weight, state, created_at)
SELECT gen_random_uuid(), ufi.user_id, ufi.interest_slug, 0.5, 'favorite', NOW()
FROM user_favorite_interests ufi
WHERE ufi.interest_slug IS NOT NULL
ON CONFLICT (user_id, interest_slug) DO UPDATE
  SET state = 'favorite' WHERE user_interests.state != 'favorite'
"""


async def _run_full_backfill(db_session):
    """Joue la séquence complète de backfill identique à upgrade()."""
    await db_session.execute(text(BACKFILL_FAVORITES_SQL))
    await db_session.execute(text(SYNC_STATE_FAVORITE_INTERESTS_SQL))
    await db_session.execute(text(SYNC_STATE_FAVORITE_TOPICS_SQL))
    await db_session.execute(text(INSERT_FALLBACK_USER_INTERESTS_SQL))
    await db_session.commit()


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


# ---------------------------------------------------------------------------
# Backfill favoris (PR 22.1.3) — décision PO 2026-05-16
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_backfill_promotes_custom_topics_at_priority_2(db_session):
    """Sujet à priority_multiplier=2.0 → favori position 0, state='favorite'."""
    user_id = uuid4()
    db_session.add(UserProfile(user_id=user_id, onboarding_completed=True))
    topic = UserTopicProfile(
        user_id=user_id,
        topic_name="Climat",
        slug_parent="environment",
        priority_multiplier=2.0,
    )
    db_session.add(topic)
    await db_session.commit()

    await _run_full_backfill(db_session)

    favs = (
        await db_session.execute(
            text(
                "SELECT position, custom_topic_id, interest_slug "
                "FROM user_favorite_interests WHERE user_id = :uid "
                "ORDER BY position"
            ),
            {"uid": user_id},
        )
    ).all()
    # Le user a 1 Sujet à 2.0 → favori pos 0, puis fallback canonical (tech, science)
    # ne s'applique pas car total >= 2 après theme_favs ou fallback.
    # Ici 0 Thème ML → fallback ajoute tech à pos 1 pour atteindre 2.
    assert len(favs) == 2
    assert favs[0][0] == 0
    assert favs[0][1] == topic.id
    assert favs[0][2] is None
    assert favs[1][0] == 1
    assert favs[1][1] is None
    assert favs[1][2] == "tech"

    topic_state = (
        await db_session.execute(
            text("SELECT state::text FROM user_topic_profiles WHERE id = :tid"),
            {"tid": topic.id},
        )
    ).scalar_one()
    assert topic_state == "favorite"


@pytest.mark.asyncio
async def test_backfill_fills_to_min_2_with_top_weight_themes(db_session):
    """User avec 1 Sujet à 2.0 + 5 Thèmes (weights variables) → le 2e favori
    est le Thème de plus fort weight (pas le 3e, le 4e, etc.)."""
    user_id = uuid4()
    db_session.add(UserProfile(user_id=user_id, onboarding_completed=True))
    topic = UserTopicProfile(
        user_id=user_id,
        topic_name="IA",
        slug_parent="tech",
        priority_multiplier=2.0,
    )
    db_session.add(topic)
    db_session.add_all(
        [
            UserInterest(user_id=user_id, interest_slug="tech", weight=0.8),
            UserInterest(user_id=user_id, interest_slug="science", weight=1.5),
            UserInterest(user_id=user_id, interest_slug="culture", weight=2.7),  # top
            UserInterest(user_id=user_id, interest_slug="economy", weight=1.1),
            UserInterest(user_id=user_id, interest_slug="sport", weight=0.6),
        ]
    )
    await db_session.commit()

    await _run_full_backfill(db_session)

    favs = (
        await db_session.execute(
            text(
                "SELECT position, custom_topic_id, interest_slug "
                "FROM user_favorite_interests WHERE user_id = :uid "
                "ORDER BY position"
            ),
            {"uid": user_id},
        )
    ).all()
    assert len(favs) == 2
    assert favs[0] == (0, topic.id, None)
    assert favs[1] == (1, None, "culture")  # plus fort weight, pas tech/science

    # state='favorite' propagé sur user_interests pour le Thème promu
    culture_state = (
        await db_session.execute(
            text(
                "SELECT state::text FROM user_interests "
                "WHERE user_id = :uid AND interest_slug = 'culture'"
            ),
            {"uid": user_id},
        )
    ).scalar_one()
    assert culture_state == "favorite"


@pytest.mark.asyncio
async def test_backfill_fallback_to_canonical_themes_for_users_with_no_signal(
    db_session,
):
    """User sans user_interests ni user_topic_profiles → 2 favoris canoniques
    (tech, science = 2 premiers de CANONICAL_THEME_SLUGS) en position 0 et 1.
    Les user_interests correspondants sont créés à state='favorite'."""
    user_id = uuid4()
    db_session.add(UserProfile(user_id=user_id, onboarding_completed=False))
    await db_session.commit()

    await _run_full_backfill(db_session)

    favs = (
        await db_session.execute(
            text(
                "SELECT position, interest_slug FROM user_favorite_interests "
                "WHERE user_id = :uid ORDER BY position"
            ),
            {"uid": user_id},
        )
    ).all()
    assert favs == [(0, "tech"), (1, "science")]

    # Les user_interests pour tech/science sont créés à state='favorite'.
    created = (
        await db_session.execute(
            text(
                "SELECT interest_slug, state::text, weight FROM user_interests "
                "WHERE user_id = :uid ORDER BY interest_slug"
            ),
            {"uid": user_id},
        )
    ).all()
    by_slug = {r[0]: (r[1], r[2]) for r in created}
    assert by_slug["science"] == ("favorite", 0.5)
    assert by_slug["tech"] == ("favorite", 0.5)


@pytest.mark.asyncio
async def test_backfill_respects_cap_of_3(db_session):
    """User avec 5 Sujets à priority=2.0 → exactement 3 favoris (cap dur,
    CHECK constraint sur position 0..2). Les 2 plus anciens / moindres
    sont ignorés silencieusement (pas d'erreur)."""
    user_id = uuid4()
    db_session.add(UserProfile(user_id=user_id, onboarding_completed=True))
    topics = []
    for i in range(5):
        t = UserTopicProfile(
            user_id=user_id,
            topic_name=f"Sujet {i}",
            slug_parent="society",
            priority_multiplier=2.0,
        )
        db_session.add(t)
        topics.append(t)
    await db_session.commit()

    await _run_full_backfill(db_session)

    cnt = (
        await db_session.execute(
            text(
                "SELECT COUNT(*) FROM user_favorite_interests "
                "WHERE user_id = :uid"
            ),
            {"uid": user_id},
        )
    ).scalar_one()
    assert cnt == 3

    positions = (
        await db_session.execute(
            text(
                "SELECT position FROM user_favorite_interests "
                "WHERE user_id = :uid ORDER BY position"
            ),
            {"uid": user_id},
        )
    ).all()
    assert [p[0] for p in positions] == [0, 1, 2]


@pytest.mark.asyncio
async def test_backfill_is_idempotent_on_rerun(db_session):
    """Re-jouer le backfill ne crée pas de doublons ni d'erreurs grâce à
    ON CONFLICT DO NOTHING sur (user_id, position). Garantit la survie au
    cycle downgrade → upgrade et à un boot Railway qui re-rejouerait par
    erreur la même migration."""
    user_id = uuid4()
    db_session.add(UserProfile(user_id=user_id, onboarding_completed=True))
    topic = UserTopicProfile(
        user_id=user_id,
        topic_name="Climat",
        slug_parent="environment",
        priority_multiplier=2.0,
    )
    db_session.add(topic)
    db_session.add(
        UserInterest(user_id=user_id, interest_slug="culture", weight=2.5)
    )
    await db_session.commit()

    await _run_full_backfill(db_session)

    snapshot_first = (
        await db_session.execute(
            text(
                "SELECT position, custom_topic_id, interest_slug "
                "FROM user_favorite_interests WHERE user_id = :uid "
                "ORDER BY position"
            ),
            {"uid": user_id},
        )
    ).all()
    assert len(snapshot_first) == 2

    # Re-run : aucun nouveau row, aucune erreur.
    await _run_full_backfill(db_session)

    snapshot_second = (
        await db_session.execute(
            text(
                "SELECT position, custom_topic_id, interest_slug "
                "FROM user_favorite_interests WHERE user_id = :uid "
                "ORDER BY position"
            ),
            {"uid": user_id},
        )
    ).all()
    assert snapshot_second == snapshot_first
