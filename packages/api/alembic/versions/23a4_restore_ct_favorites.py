"""Restaure les custom_topic favoris perdus par la migration 23a3.

La migration 23a3_custom_topic_fav_drop a :
1. Forcé `user_topic_profiles.state` de `favorite` → `followed`
2. SUPPRIMÉ les rows `user_favorite_interests` avec `custom_topic_id IS NOT NULL`

Mais elle a oublié de reset `priority_multiplier`, qui reste à 2.0 pour les
profils ex-favoris. C'est une signature non-ambiguë : aucun autre code path
n'écrivait `priority_multiplier=2.0` sur un profile en state `followed`
(audit grep + git log au 2026-05-20). On exploite cette signature pour
réhydrater les 62 favoris perdus (15 users impactés selon snapshot prod).

Revision ID: 23a4_restore_ct_favorites
Revises: vt01_user_app_version
Create Date: 2026-05-20

"""

from alembic import op

revision: str = "23a4_restore_ct_favorites"
down_revision: str | None = "vt01_user_app_version"
branch_labels: str | None = None
depends_on: str | None = None


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


def upgrade() -> None:
    op.execute(RESTORE_FAVORITE_INTERESTS_SQL)
    op.execute(PROMOTE_STATE_SQL)


def downgrade() -> None:
    # Le downgrade fait l'opération inverse de 23a3 : on annule la restauration
    # en passant les rows promues de `favorite` → `followed` ET en supprimant
    # leurs entrées dans user_favorite_interests. Idempotent.
    op.execute(
        """
        UPDATE user_topic_profiles
        SET state = 'followed'
        WHERE state = 'favorite' AND priority_multiplier = 2.0;
        """
    )
    op.execute(
        """
        DELETE FROM user_favorite_interests
        WHERE custom_topic_id IS NOT NULL;
        """
    )
