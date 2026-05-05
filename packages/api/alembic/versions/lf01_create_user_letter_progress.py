"""create user_letter_progress table (Lettres du Facteur)

Revision ID: lf01
Revises: tr01
Create Date: 2026-05-02

Une row par (user_id, letter_id). Les lettres elles-mêmes sont des constantes
Python (`app/services/letters/catalog.py`) — la DB stocke uniquement la
progression. `completed_actions` est un jsonb d'ids d'actions cochées par
auto-détection.
"""

from collections.abc import Sequence

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "lf01"
down_revision: str | Sequence[str] | None = "tr01"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "user_letter_progress",
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("user_profiles.user_id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("letter_id", sa.Text(), nullable=False),
        sa.Column(
            "status",
            sa.Text(),
            nullable=False,
        ),
        sa.Column(
            "completed_actions",
            postgresql.JSONB(),
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("archived_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.PrimaryKeyConstraint("user_id", "letter_id", name="pk_user_letter_progress"),
        sa.CheckConstraint(
            "status IN ('upcoming', 'active', 'archived')",
            name="ck_user_letter_progress_status",
        ),
    )
    op.create_index(
        "ix_user_letter_progress_user_status",
        "user_letter_progress",
        ["user_id", "status"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_user_letter_progress_user_status",
        table_name="user_letter_progress",
    )
    op.drop_table("user_letter_progress")
