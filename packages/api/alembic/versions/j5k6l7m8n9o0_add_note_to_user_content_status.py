"""add_note_to_user_content_status

Revision ID: j5k6l7m8n9o0
Revises: i4j5k6l7m8n9
Create Date: 2026-02-20 15:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'j5k6l7m8n9o0'
down_revision: Union[str, None] = 'i4j5k6l7m8n9'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('user_content_status', sa.Column('note_text', sa.Text(), nullable=True))
    op.add_column('user_content_status', sa.Column('note_updated_at', sa.DateTime(timezone=True), nullable=True))
    # Partial index for "articles with notes" queries (filter + sort by note date)
    op.create_index(
        'ix_user_content_status_user_has_note',
        'user_content_status',
        ['user_id', 'note_updated_at'],
        postgresql_where=sa.text("note_text IS NOT NULL AND note_text != ''"),
    )


def downgrade() -> None:
    op.drop_index('ix_user_content_status_user_has_note', table_name='user_content_status')
    op.drop_column('user_content_status', 'note_updated_at')
    op.drop_column('user_content_status', 'note_text')
