"""create_user_subtopics

Revision ID: k8l9m0n1o2p3
Revises: e2f3g4h5i6j7
Create Date: 2026-01-19 19:32:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID


# revision identifiers, used by Alembic.
revision: str = 'k8l9m0n1o2p3'
down_revision: Union[str, Sequence[str], None] = 'e2f3g4h5i6j7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Create user_subtopics table for user topic preferences."""
    op.create_table(
        'user_subtopics',
        sa.Column('id', UUID(as_uuid=True), primary_key=True),
        sa.Column('user_id', UUID(as_uuid=True), nullable=False),
        sa.Column('topic_slug', sa.String(length=50), nullable=False),
        sa.Column('weight', sa.Float(), nullable=False, server_default='1.0'),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False, server_default=sa.text('now()')),
        sa.ForeignKeyConstraint(['user_id'], ['user_profiles.user_id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('user_id', 'topic_slug', name='uq_user_subtopics_user_topic')
    )


def downgrade() -> None:
    """Drop user_subtopics table."""
    op.drop_table('user_subtopics')
