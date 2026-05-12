"""Entity schema foundation for topic subscriptions.

Revision ID: ts01
Revises: lc01
Create Date: 2026-03-19

-- ============================================================
-- Manual SQL for Supabase SQL Editor (Guardrail #4)
-- Execute this BEFORE deploying the code.
-- ============================================================
--
-- 1. Re-add entities column to contents
-- ALTER TABLE contents ADD COLUMN entities TEXT[] DEFAULT NULL;
-- CREATE INDEX ix_contents_entities ON contents USING GIN (entities);
--
-- 2. Add entity columns to user_topic_profiles
-- ALTER TABLE user_topic_profiles ADD COLUMN entity_type VARCHAR(20) DEFAULT NULL;
-- ALTER TABLE user_topic_profiles ADD COLUMN canonical_name VARCHAR(200) DEFAULT NULL;
--
-- 3. Replace unique constraint with partial unique indexes
-- ALTER TABLE user_topic_profiles DROP CONSTRAINT uq_user_topic_user_slug;
-- CREATE UNIQUE INDEX ix_utp_unique_topic ON user_topic_profiles (user_id, slug_parent) WHERE canonical_name IS NULL;
-- CREATE UNIQUE INDEX ix_utp_unique_entity ON user_topic_profiles (user_id, canonical_name) WHERE canonical_name IS NOT NULL;
-- ============================================================
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = 'ts01'
down_revision: Union[str, Sequence[str]] = 'lc01'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 1. Re-add entities column to contents
    op.add_column(
        'contents',
        sa.Column('entities', postgresql.ARRAY(sa.Text), nullable=True),
    )
    op.create_index(
        'ix_contents_entities', 'contents', ['entities'],
        unique=False, postgresql_using='gin',
    )

    # 2. Add entity columns to user_topic_profiles
    op.add_column(
        'user_topic_profiles',
        sa.Column('entity_type', sa.String(20), nullable=True),
    )
    op.add_column(
        'user_topic_profiles',
        sa.Column('canonical_name', sa.String(200), nullable=True),
    )

    # 3. Replace unique constraint with partial unique indexes
    op.drop_constraint('uq_user_topic_user_slug', 'user_topic_profiles', type_='unique')
    op.create_index(
        'ix_utp_unique_topic', 'user_topic_profiles',
        ['user_id', 'slug_parent'], unique=True,
        postgresql_where=sa.text('canonical_name IS NULL'),
    )
    op.create_index(
        'ix_utp_unique_entity', 'user_topic_profiles',
        ['user_id', 'canonical_name'], unique=True,
        postgresql_where=sa.text('canonical_name IS NOT NULL'),
    )


def downgrade() -> None:
    op.drop_index('ix_utp_unique_entity', table_name='user_topic_profiles')
    op.drop_index('ix_utp_unique_topic', table_name='user_topic_profiles')
    op.create_unique_constraint(
        'uq_user_topic_user_slug', 'user_topic_profiles',
        ['user_id', 'slug_parent'],
    )
    op.drop_column('user_topic_profiles', 'canonical_name')
    op.drop_column('user_topic_profiles', 'entity_type')
    op.drop_index('ix_contents_entities', table_name='contents')
    op.drop_column('contents', 'entities')
