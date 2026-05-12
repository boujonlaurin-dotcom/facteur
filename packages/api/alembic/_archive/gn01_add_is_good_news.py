"""add is_good_news to contents

Revision ID: gn01
Revises: en01
Create Date: 2026-05-01

"""
from collections.abc import Sequence

from alembic import op
import sqlalchemy as sa


revision: str = "gn01"
down_revision: str | Sequence[str] | None = "en01"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    """Add is_good_news boolean column to contents table.

    Independent of is_serene: is_serene means non-anxiogène, is_good_news
    means a real positive / hopeful story (progrès tangible, impact positif).
    """
    op.add_column("contents", sa.Column("is_good_news", sa.Boolean(), nullable=True))
    op.create_index(
        "ix_contents_is_good_news",
        "contents",
        ["is_good_news"],
        postgresql_where=sa.text("is_good_news = true"),
    )


def downgrade() -> None:
    op.drop_index("ix_contents_is_good_news", table_name="contents")
    op.drop_column("contents", "is_good_news")
