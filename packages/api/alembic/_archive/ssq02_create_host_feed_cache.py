"""create host_feed_resolutions cache

Revision ID: ssq02_host_feed_cache
Revises: ssq01_search_logs
Create Date: 2026-04-26 14:00:00.000000

NOTE: Apply manually via Supabase SQL Editor — NEVER on Railway.
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "ssq02_host_feed_cache"
down_revision: str | Sequence[str] | None = "ssq01_search_logs"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "host_feed_resolutions",
        sa.Column("host", sa.String(255), primary_key=True),
        sa.Column("feed_url", sa.Text(), nullable=True),
        sa.Column("type", sa.String(20), nullable=True),
        sa.Column("title", sa.String(255), nullable=True),
        sa.Column("logo_url", sa.Text(), nullable=True),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column(
            "resolved_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.Column(
            "expires_at",
            sa.DateTime(timezone=True),
            nullable=False,
        ),
    )
    op.create_index(
        "ix_host_feed_resolutions_expires_at",
        "host_feed_resolutions",
        ["expires_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_host_feed_resolutions_expires_at")
    op.drop_table("host_feed_resolutions")
