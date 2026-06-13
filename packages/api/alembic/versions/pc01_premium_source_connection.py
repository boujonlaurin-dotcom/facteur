"""premium source WebView connection config

Revision ID: pc01_premium_source_connection
Revises: vk01_link_keywords_to_topics
Create Date: 2026-06-01
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "pc01_premium_source_connection"
down_revision: str | None = "vk01_link_keywords_to_topics"
branch_labels: str | None = None
depends_on: str | None = None


def upgrade() -> None:
    op.add_column(
        "sources",
        sa.Column("premium_connection_config", postgresql.JSONB(), nullable=True),
    )
    op.add_column(
        "user_sources",
        sa.Column("subscription_connected_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "user_sources",
        sa.Column(
            "subscription_last_verified_at",
            sa.DateTime(timezone=True),
            nullable=True,
        ),
    )


def downgrade() -> None:
    op.drop_column("user_sources", "subscription_last_verified_at")
    op.drop_column("user_sources", "subscription_connected_at")
    op.drop_column("sources", "premium_connection_config")
