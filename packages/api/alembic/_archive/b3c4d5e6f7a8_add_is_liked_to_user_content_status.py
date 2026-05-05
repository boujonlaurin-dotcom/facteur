"""add is_liked to user_content_status

Revision ID: b3c4d5e6f7a8
Revises: 1a2b3c4d5e6f
Create Date: 2026-02-11 12:00:00.000000

Adds is_liked BOOLEAN and liked_at TIMESTAMPTZ columns to user_content_status,
plus a composite index for querying liked content per user.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = "b3c4d5e6f7a8"
down_revision: Union[str, None] = "1a2b3c4d5e6f"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "user_content_status",
        sa.Column("is_liked", sa.Boolean(), nullable=False, server_default="false"),
    )
    op.add_column(
        "user_content_status",
        sa.Column("liked_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index(
        "ix_user_content_status_user_liked",
        "user_content_status",
        ["user_id", "is_liked"],
    )


def downgrade() -> None:
    op.drop_index("ix_user_content_status_user_liked", table_name="user_content_status")
    op.drop_column("user_content_status", "liked_at")
    op.drop_column("user_content_status", "is_liked")
