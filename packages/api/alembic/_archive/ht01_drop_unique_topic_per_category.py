"""drop unique index ix_utp_unique_topic to allow up to 3 non-entity topics per category

Revision ID: ht01
Revises: mg02
Create Date: 2026-04-03

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "ht01"
down_revision: Union[str, Sequence[str]] = "mg02"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.drop_index("ix_utp_unique_topic", table_name="user_topic_profiles")


def downgrade() -> None:
    op.create_index(
        "ix_utp_unique_topic",
        "user_topic_profiles",
        ["user_id", "slug_parent"],
        unique=True,
        postgresql_where=sa.text("canonical_name IS NULL"),
    )
