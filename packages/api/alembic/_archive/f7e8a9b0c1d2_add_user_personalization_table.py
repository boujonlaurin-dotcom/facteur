"""add user_personalization table

Revision ID: f7e8a9b0c1d2
Revises: a4b5c6d7e8f9
Create Date: 2026-01-22 23:35:00.000000

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = 'f7e8a9b0c1d2'
down_revision = 'a4b5c6d7e8f9'  # Previous migration
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'user_personalization',
        sa.Column('user_id', postgresql.UUID(as_uuid=True), sa.ForeignKey('user_profiles.id', ondelete='CASCADE'), primary_key=True),
        sa.Column('muted_sources', postgresql.ARRAY(postgresql.UUID(as_uuid=True)), server_default='{}', nullable=False),
        sa.Column('muted_themes', postgresql.ARRAY(sa.Text()), server_default='{}', nullable=False),
        sa.Column('muted_topics', postgresql.ARRAY(sa.Text()), server_default='{}', nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.func.now(), onupdate=sa.func.now(), nullable=False),
    )


def downgrade() -> None:
    op.drop_table('user_personalization')
