"""create_source_search_logs + enable unaccent

Revision ID: ssq01_search_logs
Revises: wi01
Create Date: 2026-04-26 12:00:00.000000

NOTE: Execute SQL manually via Supabase SQL Editor — NEVER on Railway.
The CREATE EXTENSION line requires superuser; run it separately if needed.
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "ssq01_search_logs"
down_revision: Union[str, Sequence[str], None] = "wi01"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute("CREATE EXTENSION IF NOT EXISTS unaccent")

    op.create_table(
        "source_search_logs",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("query_raw", sa.String(500), nullable=False),
        sa.Column("query_normalized", sa.String(500), nullable=False),
        sa.Column("content_type", sa.String(20), nullable=True),
        sa.Column(
            "expand", sa.Boolean(), nullable=False, server_default=sa.text("false")
        ),
        sa.Column(
            "layers_called",
            postgresql.ARRAY(sa.String()),
            nullable=False,
            server_default=sa.text("'{}'::text[]"),
        ),
        sa.Column(
            "result_count", sa.Integer(), nullable=False, server_default=sa.text("0")
        ),
        sa.Column(
            "top_results",
            postgresql.JSONB(),
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
        sa.Column(
            "latency_ms", sa.Integer(), nullable=False, server_default=sa.text("0")
        ),
        sa.Column(
            "cache_hit",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
        ),
        sa.Column(
            "abandoned",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
    )
    op.create_index(
        "ix_source_search_logs_created_at", "source_search_logs", ["created_at"]
    )
    op.create_index(
        "ix_source_search_logs_query_normalized",
        "source_search_logs",
        ["query_normalized"],
    )
    op.create_index(
        "ix_source_search_logs_user_id", "source_search_logs", ["user_id"]
    )


def downgrade() -> None:
    op.drop_index("ix_source_search_logs_user_id")
    op.drop_index("ix_source_search_logs_query_normalized")
    op.drop_index("ix_source_search_logs_created_at")
    op.drop_table("source_search_logs")
