"""create_source_search_cache

Revision ID: ss01_search_cache
Revises: z1a2b3c4d5e6
Create Date: 2026-04-15 10:00:00.000000

NOTE: Execute SQL manually via Supabase SQL Editor — NEVER on Railway.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "ss01_search_cache"
down_revision: Union[str, Sequence[str], None] = "sf02"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "source_search_cache",
        sa.Column("query_hash", sa.String(64), primary_key=True),
        sa.Column("query_raw", sa.Text(), nullable=False),
        sa.Column("payload", postgresql.JSONB(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
    )
    op.create_index(
        "ix_source_search_cache_expires_at",
        "source_search_cache",
        ["expires_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_source_search_cache_expires_at")
    op.drop_table("source_search_cache")
