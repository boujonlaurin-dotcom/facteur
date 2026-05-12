"""Reactivate Les Échos source (was disabled by fix_stale_rss_sources.sql but feed URL now fixed).

Revision ID: g2h3i4j5k6l7
Revises: f1e2d3c4b5a6
Create Date: 2026-02-19
"""
from typing import Sequence, Union

from alembic import op


revision: str = 'g2h3i4j5k6l7'
down_revision: Union[str, Sequence[str], None] = 'f1e2d3c4b5a6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute("""
        UPDATE sources SET is_active = true
        WHERE (name ILIKE '%les échos%' OR name ILIKE '%les echos%')
          AND feed_url IS NOT NULL;
    """)


def downgrade() -> None:
    op.execute("""
        UPDATE sources SET is_active = false
        WHERE (name ILIKE '%les échos%' OR name ILIKE '%les echos%');
    """)
