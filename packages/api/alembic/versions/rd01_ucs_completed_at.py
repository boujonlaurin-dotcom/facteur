"""user_content_status: completed_at + completion_source (« lu jusqu'au bout »)

Epic 30 — La lecture aboutie.

Additif pur, aucun backfill : `completed_at IS NULL` signifie « inconnu », pas
« non terminé ». Un backfill depuis `reading_progress` serait faux, la colonne
étant plafonnée à 25 pour ~90 % du catalogue (contenu partiel).

`completed_at` est orthogonal à `status` : les filtres d'exclusion du feed et du
digest (`status.in_([SEEN, CONSUMED])`) ne le voient pas, donc aucun impact sur
la recommandation ni sur la complétion implicite du digest.

Revision ID: rd01_ucs_completed_at
Revises: 181c618da382
Create Date: 2026-07-24
"""

from collections.abc import Sequence

from alembic import op

revision: str = "rd01_ucs_completed_at"
down_revision: str | None = "181c618da382"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # Rejouable (IF NOT EXISTS) : la DB Supabase est partagée staging↔prod et le
    # Dockerfile rejoue `alembic upgrade head` au boot des deux services.
    op.execute(
        "ALTER TABLE user_content_status ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ"
    )
    op.execute(
        "ALTER TABLE user_content_status "
        "ADD COLUMN IF NOT EXISTS completion_source VARCHAR(12)"
    )
    # Partial index — only completed rows are indexed, so the cost stays
    # negligible while the derived daily counter reads it directly.
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_ucs_user_completed_at "
        "ON user_content_status (user_id, completed_at) "
        "WHERE completed_at IS NOT NULL"
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_ucs_user_completed_at")
    op.execute(
        "ALTER TABLE user_content_status DROP COLUMN IF EXISTS completion_source"
    )
    op.execute("ALTER TABLE user_content_status DROP COLUMN IF EXISTS completed_at")
