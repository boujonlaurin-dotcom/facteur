"""epic8_progression

Revision ID: a1b2c3d4e5f6
Revises: f8a2b3c4d5e6
Create Date: 2026-01-17 13:35:00.000000

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = 'a1b2c3d4e5f6'
down_revision = 'f8a2b3c4d5e6'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # --- 1. Modify Sources Table ---
    op.add_column('sources', sa.Column('granular_topics', postgresql.ARRAY(sa.Text()), nullable=True))

    # --- 2. Create User Topic Progress Table ---
    op.create_table(
        'user_topic_progress',
        sa.Column('id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('topic', sa.String(length=100), nullable=False),
        sa.Column('level', sa.Integer(), nullable=False, server_default='1'),
        sa.Column('points', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=True),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('user_id', 'topic', name='uq_user_topic_progress_user_topic')
    )
    op.create_index('ix_user_topic_progress_topic', 'user_topic_progress', ['topic'], unique=False)
    op.create_index('ix_user_topic_progress_user_id', 'user_topic_progress', ['user_id'], unique=False)

    # --- 3. Create Topic Quizzes Table ---
    op.create_table(
        'topic_quizzes',
        sa.Column('id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('topic', sa.String(length=100), nullable=False),
        sa.Column('question', sa.Text(), nullable=False),
        sa.Column('options', postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column('correct_answer', sa.Integer(), nullable=False),
        sa.Column('difficulty', sa.Integer(), nullable=False, server_default='1'),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=True),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index('ix_topic_quizzes_topic', 'topic_quizzes', ['topic'], unique=False)


def downgrade() -> None:
    # --- Drop Topic Quizzes ---
    op.drop_index('ix_topic_quizzes_topic', table_name='topic_quizzes')
    op.drop_table('topic_quizzes')

    # --- Drop User Topic Progress ---
    op.drop_index('ix_user_topic_progress_user_id', table_name='user_topic_progress')
    op.drop_index('ix_user_topic_progress_topic', table_name='user_topic_progress')
    op.drop_table('user_topic_progress')

    # --- Revert Sources ---
    op.drop_column('sources', 'granular_topics')
