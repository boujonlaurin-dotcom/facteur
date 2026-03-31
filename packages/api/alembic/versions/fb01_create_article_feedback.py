"""create article_feedback table

Revision ID: fb01
Revises: z1a2b3c4d5e6
Create Date: 2026-03-31 10:00:00.000000

"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "fb01"
down_revision: Union[str, None] = "z1a2b3c4d5e6"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "article_feedback",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column(
            "content_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("contents.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("sentiment", sa.String(10), nullable=False),
        sa.Column("reasons", postgresql.ARRAY(sa.Text), nullable=True),
        sa.Column("comment", sa.Text, nullable=True),
        sa.Column("digest_date", sa.Date, nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )
    op.create_unique_constraint(
        "uq_article_feedback_user_content",
        "article_feedback",
        ["user_id", "content_id"],
    )
    op.create_index(
        "ix_article_feedback_content_id",
        "article_feedback",
        ["content_id"],
    )


def downgrade() -> None:
    op.drop_index("ix_article_feedback_content_id", table_name="article_feedback")
    op.drop_constraint(
        "uq_article_feedback_user_content", "article_feedback", type_="unique"
    )
    op.drop_table("article_feedback")
