"""Add reading_progress to user_content_status.

Revision ID: rp01
Revises: bk01
Create Date: 2026-03-11
"""

from alembic import op
import sqlalchemy as sa

revision: str = "rp01"
down_revision: str = "bk01"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "user_content_status",
        sa.Column(
            "reading_progress",
            sa.SmallInteger(),
            server_default="0",
            nullable=False,
        ),
    )


def downgrade() -> None:
    op.drop_column("user_content_status", "reading_progress")
