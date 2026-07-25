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

import sqlalchemy as sa
from alembic import op

revision: str = "rd01_ucs_completed_at"
down_revision: str | None = "181c618da382"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "user_content_status",
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "user_content_status",
        sa.Column("completion_source", sa.String(length=12), nullable=True),
    )
    # Partial index — only completed rows are indexed, so the cost stays
    # negligible while the derived daily counter reads it directly.
    op.create_index(
        "ix_ucs_user_completed_at",
        "user_content_status",
        ["user_id", "completed_at"],
        unique=False,
        postgresql_where=sa.text("completed_at IS NOT NULL"),
    )


def downgrade() -> None:
    op.drop_index("ix_ucs_user_completed_at", table_name="user_content_status")
    op.drop_column("user_content_status", "completion_source")
    op.drop_column("user_content_status", "completed_at")
