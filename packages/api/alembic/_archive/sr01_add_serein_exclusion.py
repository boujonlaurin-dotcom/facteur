"""add excluded_from_serein to user_topic_profiles (Story 15.1 Mode Serein Refine)

Revision ID: sr01_add_serein_exclusion
Revises: ln01, ss01_search_cache
Create Date: 2026-04-19 12:00:00.000000

Also merges the two prior heads (ln01, ss01_search_cache) back into one.
"""

from collections.abc import Sequence
from typing import Union

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "sr01_add_serein_exclusion"
down_revision: Union[str, Sequence[str], None] = ("ln01", "ss01_search_cache")
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "user_topic_profiles",
        sa.Column(
            "excluded_from_serein",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
        ),
    )


def downgrade() -> None:
    op.drop_column("user_topic_profiles", "excluded_from_serein")
