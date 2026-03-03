"""add user_topic_profiles table (Epic 11 Custom Topics)

Revision ID: e11a0001
Revises: 1a2b3c4d5e6f
Create Date: 2026-03-02 12:00:00.000000
"""

from collections.abc import Sequence
from typing import Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "e11a0001"
down_revision: Union[str, None] = "1a2b3c4d5e6f"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    if inspector.has_table("user_topic_profiles"):
        return

    op.create_table(
        "user_topic_profiles",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("user_profiles.user_id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("topic_name", sa.String(200), nullable=False),
        sa.Column("slug_parent", sa.String(50), nullable=False),
        sa.Column("keywords", postgresql.ARRAY(sa.Text), nullable=True),
        sa.Column("intent_description", sa.Text, nullable=True),
        sa.Column("source_type", sa.String(20), nullable=False, server_default="explicit"),
        sa.Column("priority_multiplier", sa.Float, nullable=False, server_default="1.0"),
        sa.Column("composite_score", sa.Float, nullable=False, server_default="0.0"),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.UniqueConstraint("user_id", "slug_parent", name="uq_user_topic_user_slug"),
    )
    op.create_index(
        "ix_user_topic_profiles_user_id",
        "user_topic_profiles",
        ["user_id"],
    )


def downgrade() -> None:
    op.drop_index("ix_user_topic_profiles_user_id", table_name="user_topic_profiles")
    op.drop_table("user_topic_profiles")
