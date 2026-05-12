"""add editorial_note to sources

Revision ID: en01
Revises: pr01
Create Date: 2026-04-29

Adds:
- sources.editorial_note (text, nullable) — note éditoriale "Pourquoi on apprécie"
  affichée dans la modal de présentation d'une source.
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "en01"
down_revision: str = "pr01"
branch_labels: Sequence[str] | None = None
depends_on: str | None = None


def upgrade() -> None:
    op.add_column(
        "sources",
        sa.Column("editorial_note", sa.Text(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("sources", "editorial_note")
