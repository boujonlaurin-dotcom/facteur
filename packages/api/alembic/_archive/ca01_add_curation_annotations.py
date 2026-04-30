"""add_curation_annotations

Revision ID: ca01
Revises: f6170e07e614
Create Date: 2026-03-04 18:00:00.000000

Backoffice: curation_annotations table for algo quality tracking.
"""

from collections.abc import Sequence
from typing import Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = 'ca01'
down_revision: Union[str, Sequence[str], None] = 'c134526be6cd'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'curation_annotations',
        sa.Column('id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('content_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('feed_date', sa.Date(), nullable=False),
        sa.Column('label', sa.String(10), nullable=False),
        sa.Column('note', sa.Text(), nullable=True),
        sa.Column('annotated_by', sa.String(50), server_default='admin', nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['content_id'], ['contents.id'], ondelete='CASCADE'),
        sa.CheckConstraint("label IN ('good', 'bad', 'missing')", name='ck_curation_label'),
    )
    op.create_index('ix_curation_annotations_user_id', 'curation_annotations', ['user_id'])
    op.create_index('ix_curation_annotations_feed_date', 'curation_annotations', ['feed_date'])
    op.create_unique_constraint(
        'uq_curation_user_content_date',
        'curation_annotations',
        ['user_id', 'content_id', 'feed_date'],
    )


def downgrade() -> None:
    op.drop_constraint('uq_curation_user_content_date', 'curation_annotations', type_='unique')
    op.drop_index('ix_curation_annotations_feed_date', table_name='curation_annotations')
    op.drop_index('ix_curation_annotations_user_id', table_name='curation_annotations')
    op.drop_table('curation_annotations')
