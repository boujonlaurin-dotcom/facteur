"""Add composite index on daily_digest target date and serene variant."""

from __future__ import annotations

from alembic import op


revision: str = "dg02_daily_digest_date_serene_index"
down_revision: str | None = "pc01_premium_source_connection"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_index(
        "ix_daily_digest_target_date_is_serene",
        "daily_digest",
        ["target_date", "is_serene"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("ix_daily_digest_target_date_is_serene", table_name="daily_digest")
