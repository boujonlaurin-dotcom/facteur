"""drop obsolete article extraction timestamp

Revision ID: ex01_drop_extraction_ts
Revises: gh01_grille_hybrid_word
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "ex01_drop_extraction_ts"
down_revision: str | None = "gh01_grille_hybrid_word"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.drop_column("contents", "extraction_attempted_at")


def downgrade() -> None:
    op.add_column(
        "contents",
        sa.Column("extraction_attempted_at", sa.DateTime(timezone=True), nullable=True),
    )
