"""Add UTM columns to waitlist_entries and create waitlist_survey_responses table.

Revision ID: wl02
Revises: wl01, rp01
Create Date: 2026-03-13

SQL to run manually in Supabase SQL Editor:

ALTER TABLE waitlist_entries
    ADD COLUMN IF NOT EXISTS utm_source VARCHAR(100),
    ADD COLUMN IF NOT EXISTS utm_medium VARCHAR(100),
    ADD COLUMN IF NOT EXISTS utm_campaign VARCHAR(100);

CREATE TABLE IF NOT EXISTS waitlist_survey_responses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    waitlist_entry_id UUID NOT NULL REFERENCES waitlist_entries(id) ON DELETE CASCADE,
    info_source VARCHAR(100) NOT NULL,
    main_pain TEXT NOT NULL,
    willingness VARCHAR(100) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_waitlist_survey_entry_id
    ON waitlist_survey_responses (waitlist_entry_id);
"""

from typing import Sequence, Union

from alembic import op


# revision identifiers, used by Alembic.
revision: str = 'wl02'
down_revision: Union[str, Sequence[str]] = ('wl01', 'rp01')
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # UTM columns on waitlist_entries
    op.execute("""
        ALTER TABLE waitlist_entries
            ADD COLUMN IF NOT EXISTS utm_source VARCHAR(100),
            ADD COLUMN IF NOT EXISTS utm_medium VARCHAR(100),
            ADD COLUMN IF NOT EXISTS utm_campaign VARCHAR(100)
    """)

    # Survey responses table
    op.execute("""
        CREATE TABLE IF NOT EXISTS waitlist_survey_responses (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            waitlist_entry_id UUID NOT NULL
                REFERENCES waitlist_entries(id) ON DELETE CASCADE,
            info_source VARCHAR(100) NOT NULL,
            main_pain TEXT NOT NULL,
            willingness VARCHAR(100) NOT NULL,
            created_at TIMESTAMPTZ DEFAULT now()
        )
    """)
    op.execute("""
        CREATE INDEX IF NOT EXISTS ix_waitlist_survey_entry_id
            ON waitlist_survey_responses (waitlist_entry_id)
    """)


def downgrade() -> None:
    op.drop_index('ix_waitlist_survey_entry_id',
                  table_name='waitlist_survey_responses')
    op.drop_table('waitlist_survey_responses')
    op.execute("ALTER TABLE waitlist_entries DROP COLUMN IF EXISTS utm_source")
    op.execute("ALTER TABLE waitlist_entries DROP COLUMN IF EXISTS utm_medium")
    op.execute("ALTER TABLE waitlist_entries DROP COLUMN IF EXISTS utm_campaign")
