"""add tone and serein_default to sources

Revision ID: td01
Revises: mg03
Create Date: 2026-04-08

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision: str = "td01"
down_revision: str = "mg03"
branch_labels: Sequence[str] | None = None
depends_on: str | None = None


def upgrade() -> None:
    op.add_column(
        "sources",
        sa.Column("tone", sa.String(20), nullable=True),
    )
    op.add_column(
        "sources",
        sa.Column("serein_default", sa.Boolean(), server_default="false", nullable=False),
    )
    op.create_index("ix_sources_tone", "sources", ["tone"])
    op.create_index("ix_sources_serein_default", "sources", ["serein_default"])


def downgrade() -> None:
    op.drop_index("ix_sources_serein_default", table_name="sources")
    op.drop_index("ix_sources_tone", table_name="sources")
    op.drop_column("sources", "serein_default")
    op.drop_column("sources", "tone")
