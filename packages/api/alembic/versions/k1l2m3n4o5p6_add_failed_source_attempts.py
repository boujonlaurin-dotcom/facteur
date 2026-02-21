"""add_failed_source_attempts

Revision ID: k1l2m3n4o5p6
Revises: j5k6l7m8n9o0
Create Date: 2026-02-21 12:00:00.000000

Epic 12: Add Source 2.0 — Track failed URL/keyword attempts for discovery improvement.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = 'k1l2m3n4o5p6'
down_revision: Union[str, None] = 'j5k6l7m8n9o0'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'failed_source_attempts',
        sa.Column('id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('input_text', sa.String(500), nullable=False),
        sa.Column('input_type', sa.String(20), nullable=False),
        sa.Column('endpoint', sa.String(20), nullable=False),
        sa.Column('error_message', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_failed_source_attempts_user_id', 'failed_source_attempts', ['user_id'])
    op.create_index('ix_failed_source_attempts_created_at', 'failed_source_attempts', ['created_at'])
    op.create_index('ix_failed_source_attempts_input_text', 'failed_source_attempts', ['input_text'])


def downgrade() -> None:
    op.drop_index('ix_failed_source_attempts_input_text', table_name='failed_source_attempts')
    op.drop_index('ix_failed_source_attempts_created_at', table_name='failed_source_attempts')
    op.drop_index('ix_failed_source_attempts_user_id', table_name='failed_source_attempts')
    op.drop_table('failed_source_attempts')
