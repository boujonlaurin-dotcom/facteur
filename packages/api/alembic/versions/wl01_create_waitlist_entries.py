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
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID


# revision identifiers, used by Alembic.
revision: str = 'wl01'
down_revision: Union[str, Sequence[str]] = 'bk01'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'waitlist_entries',
        sa.Column('id', UUID(as_uuid=True), primary_key=True, server_default=sa.text('gen_random_uuid()')),
        sa.Column('email', sa.String(255), nullable=False, unique=True),
        sa.Column('source', sa.String(50), server_default='landing'),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()')),
    )
    op.create_index('ix_waitlist_entries_email', 'waitlist_entries', ['email'])


def downgrade() -> None:
    op.drop_index('ix_waitlist_entries_email', table_name='waitlist_entries')
    op.drop_table('waitlist_entries')
