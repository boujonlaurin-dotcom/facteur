"""Create waitlist_entries table for landing page signups.

Revision ID: wl01
Revises: bk01
Create Date: 2026-03-12

SQL to run manually in Supabase SQL Editor:

CREATE TABLE waitlist_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) NOT NULL UNIQUE,
    source VARCHAR(50) DEFAULT 'landing',
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX ix_waitlist_entries_email ON waitlist_entries (email);
"""

from typing import Sequence, Union

from alembic import op


# revision identifiers, used by Alembic.
revision: str = 'wl01'
down_revision: Union[str, Sequence[str]] = 'bk01'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Use IF NOT EXISTS: table may have been created manually in Supabase
    # before this migration was tracked in alembic_version.
    op.execute("""
        CREATE TABLE IF NOT EXISTS waitlist_entries (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            email VARCHAR(255) NOT NULL UNIQUE,
            source VARCHAR(50) DEFAULT 'landing',
            created_at TIMESTAMPTZ DEFAULT now()
        )
    """)
    op.execute("""
        CREATE INDEX IF NOT EXISTS ix_waitlist_entries_email ON waitlist_entries (email)
    """)


def downgrade() -> None:
    op.drop_index('ix_waitlist_entries_email', table_name='waitlist_entries')
    op.drop_table('waitlist_entries')
