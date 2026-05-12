"""enable_pg_trgm_extension

Revision ID: enable_pg_trgm
Revises: e5241a22714f
Create Date: 2026-01-11 23:25:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'enable_pg_trgm'
down_revision: Union[str, Sequence[str], None] = 'e5241a22714f'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Enable pg_trgm extension and create GIN index on title."""
    # Enable pg_trgm extension
    op.execute('CREATE EXTENSION IF NOT EXISTS pg_trgm')
    
    # Create GIN index on title for fast similarity searches
    op.execute('CREATE INDEX IF NOT EXISTS ix_contents_title_trgm ON contents USING gin (title gin_trgm_ops)')


def downgrade() -> None:
    """Remove GIN index and pg_trgm extension."""
    op.execute('DROP INDEX IF EXISTS ix_contents_title_trgm')
    # Note: We don't drop the extension as other parts might use it
