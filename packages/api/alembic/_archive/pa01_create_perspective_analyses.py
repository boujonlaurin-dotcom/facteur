"""create_perspective_analyses

Revision ID: pa01
Revises: z1a2b3c4d5e6
Create Date: 2026-04-07 10:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = 'pa01'
down_revision: Union[str, Sequence[str], None] = 'z1a2b3c4d5e6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        'perspective_analyses',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True,
                  server_default=sa.text('gen_random_uuid()')),
        sa.Column('content_id', postgresql.UUID(as_uuid=True),
                  sa.ForeignKey('contents.id', ondelete='CASCADE'),
                  nullable=False),
        sa.Column('analysis_text', sa.Text(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text('now()')),
        sa.UniqueConstraint('content_id', name='uq_perspective_analyses_content_id'),
    )
    op.create_index('ix_perspective_analyses_content_id', 'perspective_analyses',
                    ['content_id'])


def downgrade() -> None:
    op.drop_index('ix_perspective_analyses_content_id', table_name='perspective_analyses')
    op.drop_table('perspective_analyses')
