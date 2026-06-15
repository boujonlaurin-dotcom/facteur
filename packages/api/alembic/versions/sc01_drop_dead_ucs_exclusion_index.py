"""drop dead index ix_user_content_status_exclusion

Hygiène stockage (scaling phase 2, G5). L'index 5 colonnes
ix_user_content_status_exclusion n'est jamais choisi par le planner (EXPLAIN
du baseline 2026-06-04 §3 : les requêtes d'exclusion passent par
uq_user_content_status_user_content) ; il ne coûte que de la
write-amplification sur chaque interaction user. DROP idempotent, sans danger
pour l'ancien code prod (un index en moins ne casse aucune requête).

Revision ID: sc01_drop_ucs_excl_idx
Revises: mg01_merge_au01_rsvps
Create Date: 2026-06-13

"""

from alembic import op

revision: str = "sc01_drop_ucs_excl_idx"
down_revision: str | None = "mg01_merge_au01_rsvps"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_user_content_status_exclusion")


def downgrade() -> None:
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_user_content_status_exclusion "
        "ON user_content_status (user_id, content_id, is_hidden, is_saved, status)"
    )
