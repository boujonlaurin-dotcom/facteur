"""add_content_entities

Revision ID: p1q2r3s4t5u6
Revises: z1a2b3c4d5e6
Create Date: 2026-01-30 18:45:00.000000

"""
from typing import Sequence, Union

from alembic import op


# revision identifiers, used by Alembic.
revision: str = 'p1q2r3s4t5u6'
down_revision: Union[str, Sequence[str], None] = 'z1a2b3c4d5e6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """No-op: entities column disabled (NER feature deferred).

    See docs/maintenance/maintenance-ner-disabled.md for context.
    The column will be added by a future migration when NER is re-enabled
    (requires Supabase tier upgrade for large table ALTER).
    """
    pass


def downgrade() -> None:
    """Remove entities column and index from contents table (safe, uses IF EXISTS)."""
    op.execute("DROP INDEX IF EXISTS ix_contents_entities")
    op.execute("ALTER TABLE contents DROP COLUMN IF EXISTS entities")
