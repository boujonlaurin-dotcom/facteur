"""interest state enum + favorites tables (Story 22.1).

Système d'intérêts unifié à 4 états (hidden/unfollowed/followed/favorite)
appliqué à user_interests, user_topic_profiles, user_sources. Deux nouvelles
tables (user_favorite_interests, user_favorite_sources) avec PK composite
(user_id, position 0..2) garantissant le cap dur à 3 favoris par catégorie.

Audit prod 2026-05-16 : 39 doublons (user_id, interest_slug) à dédupliquer
avant la création de la UNIQUE constraint. Migration de données conservatrice :
weight ≤ 0.5 → hidden ; priority_multiplier = 0.2 → hidden ; aucun favori
auto-promu (le user devra les déclarer explicitement via la nouvelle UI).
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "22a1_interest_state_favorites"
down_revision: str | None = "ad01_add_is_ad_to_contents"
branch_labels: str | None = None
depends_on: str | None = None


# Enum partagé par les 3 tables. create_type=False : la création est faite
# explicitement via .create() pour pouvoir checkfirst=True (idempotence) ;
# les sa.Column() qui le référencent ne doivent pas le recréer.
interest_state_enum = postgresql.ENUM(
    "hidden",
    "unfollowed",
    "followed",
    "favorite",
    name="interest_state",
    create_type=False,
)


# ---------------------------------------------------------------------------
# Backfill favoris legacy → user_favorite_interests (décision PO 2026-05-16)
# ---------------------------------------------------------------------------
# Cible : >= MIN_BACKFILL_FAVORITES (2) favoris par user existant, cap à 3
# (FAVORITE_CAP). Ordre de priorité :
#   1. Sujets custom à priority_multiplier=2.0 (signal explicite stocké en DB)
#   2. Top user_interests.weight desc (proxy ML pour les Thèmes — compense
#      l'absence du slider 1→3 mobile dans la DB)
#   3. Fallback : 2 macro-thèmes Facteur canoniques (tech, science) pour les
#      users sans aucun signal (inactifs, onboarding incomplet)
#
# Slot 3 réservé à la promo mobile post-MeP (sync SharedPrefs `theme_priority_*`).
# Constantes exposées comme module-level pour permettre aux tests Alembic
# (tests/alembic/test_interest_state_migration.py) de re-jouer le SQL sans
# duplication. Doit rester synchronisé avec app/constants.py.
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

# Aligne state='favorite' sur les rows sources des favoris (Thèmes existants).
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

# Pour les fallback themes : crée la row user_interests si elle n'existe pas
# (users sans aucun signal). On laisse weight=0.5 (proxy "à confirmer") et
# state='favorite' direct.
INSERT_FALLBACK_USER_INTERESTS_SQL = """
INSERT INTO user_interests (id, user_id, interest_slug, weight, state, created_at)
SELECT gen_random_uuid(), ufi.user_id, ufi.interest_slug, 0.5, 'favorite', NOW()
FROM user_favorite_interests ufi
WHERE ufi.interest_slug IS NOT NULL
ON CONFLICT (user_id, interest_slug) DO UPDATE
  SET state = 'favorite' WHERE user_interests.state != 'favorite'
"""


def upgrade() -> None:
    bind = op.get_bind()

    interest_state_enum.create(bind, checkfirst=True)

    # Dedupe défensif sur user_interests (39 lignes en prod au 2026-05-16).
    # Garde la row de plus grand weight (signal ML) en cas de doublon.
    op.execute(
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

    op.add_column(
        "user_interests",
        sa.Column(
            "state",
            interest_state_enum,
            nullable=False,
            server_default="followed",
        ),
    )
    op.add_column(
        "user_topic_profiles",
        sa.Column(
            "state",
            interest_state_enum,
            nullable=False,
            server_default="followed",
        ),
    )
    op.add_column(
        "user_sources",
        sa.Column(
            "state",
            interest_state_enum,
            nullable=False,
            server_default="followed",
        ),
    )

    op.create_unique_constraint(
        "user_interests_user_slug_uniq",
        "user_interests",
        ["user_id", "interest_slug"],
    )

    op.create_table(
        "user_favorite_interests",
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("position", sa.SmallInteger(), nullable=False),
        sa.Column("interest_slug", sa.String(length=50), nullable=True),
        sa.Column("custom_topic_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("NOW()"),
        ),
        sa.PrimaryKeyConstraint("user_id", "position"),
        sa.ForeignKeyConstraint(
            ["user_id"], ["user_profiles.user_id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["custom_topic_id"], ["user_topic_profiles.id"], ondelete="CASCADE"
        ),
        sa.CheckConstraint(
            "position BETWEEN 0 AND 2",
            name="user_favorite_interests_position_range",
        ),
        sa.CheckConstraint(
            "(interest_slug IS NOT NULL)::int + (custom_topic_id IS NOT NULL)::int = 1",
            name="user_favorite_interests_target_xor",
        ),
    )

    op.create_table(
        "user_favorite_sources",
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("position", sa.SmallInteger(), nullable=False),
        sa.Column("source_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("NOW()"),
        ),
        sa.PrimaryKeyConstraint("user_id", "position"),
        sa.ForeignKeyConstraint(
            ["user_id"], ["user_profiles.user_id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(["source_id"], ["sources.id"], ondelete="CASCADE"),
        sa.UniqueConstraint(
            "user_id", "source_id", name="user_favorite_sources_user_source_uniq"
        ),
        sa.CheckConstraint(
            "position BETWEEN 0 AND 2",
            name="user_favorite_sources_position_range",
        ),
    )

    # Migration de données conservatrice : low-priority → hidden.
    op.execute("UPDATE user_interests SET state = 'hidden' WHERE weight <= 0.5")
    op.execute(
        "UPDATE user_sources SET state = 'hidden' WHERE priority_multiplier = 0.2"
    )
    op.execute(
        "UPDATE user_topic_profiles SET state = 'hidden' WHERE priority_multiplier = 0.2"
    )

    # Backfill favoris : peuple user_favorite_interests pour tous les users.
    # Cible >= 2 favoris/user (slot 3 réservé à la promo mobile post-MeP).
    op.execute(BACKFILL_FAVORITES_SQL)
    op.execute(SYNC_STATE_FAVORITE_INTERESTS_SQL)
    op.execute(SYNC_STATE_FAVORITE_TOPICS_SQL)
    op.execute(INSERT_FALLBACK_USER_INTERESTS_SQL)


def downgrade() -> None:
    op.drop_table("user_favorite_sources")
    op.drop_table("user_favorite_interests")
    op.drop_constraint(
        "user_interests_user_slug_uniq", "user_interests", type_="unique"
    )
    op.drop_column("user_sources", "state")
    op.drop_column("user_topic_profiles", "state")
    op.drop_column("user_interests", "state")
    interest_state_enum.drop(op.get_bind(), checkfirst=True)
