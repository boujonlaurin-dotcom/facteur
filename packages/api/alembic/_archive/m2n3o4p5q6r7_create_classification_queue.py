"""create_classification_queue

Revision ID: m2n3o4p5q6r7
Revises: z1a2b3c4d5e6
Create Date: 2026-01-29 10:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = 'm2n3o4p5q6r7'
down_revision: Union[str, None] = 'z1a2b3c4d5e6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Create classification_queue table
    op.create_table(
        'classification_queue',
        sa.Column('id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('content_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('status', sa.String(length=20), nullable=False, server_default='pending'),
        sa.Column('priority', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('retry_count', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('error_message', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('processed_at', sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(['content_id'], ['contents.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('content_id')
    )
    
    # Create indexes for efficient querying
    op.create_index('idx_queue_status_created', 'classification_queue', ['status', 'created_at'])
    # op.create_index('idx_queue_priority', 'classification_queue', [sa.text('priority DESC'), 'created_at'])


def downgrade() -> None:
    # Drop indexes
    op.drop_index('idx_queue_priority', table_name='classification_queue')
    op.drop_index('idx_queue_status_created', table_name='classification_queue')
    
    # Drop table
    op.drop_table('classification_queue')
