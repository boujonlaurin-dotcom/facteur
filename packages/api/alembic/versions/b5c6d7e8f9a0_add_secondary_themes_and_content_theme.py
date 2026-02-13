"""add secondary_themes to sources and theme to contents

Revision ID: b5c6d7e8f9a0
Revises: a424896cdfd9
Create Date: 2026-02-12 12:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = 'b5c6d7e8f9a0'
down_revision: Union[str, None] = 'a424896cdfd9'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Phase 1: secondary_themes sur sources (ARRAY de slugs thèmes)
    op.add_column('sources',
        sa.Column('secondary_themes', postgresql.ARRAY(sa.Text()), nullable=True))
    op.create_index(
        'ix_sources_secondary_themes', 'sources',
        ['secondary_themes'], postgresql_using='gin')

    # Phase 2: theme sur contents (slug inféré par ML)
    op.add_column('contents',
        sa.Column('theme', sa.String(50), nullable=True))
    op.create_index('ix_contents_theme', 'contents', ['theme'])


def downgrade() -> None:
    op.drop_index('ix_contents_theme', table_name='contents')
    op.drop_column('contents', 'theme')
    op.drop_index('ix_sources_secondary_themes', table_name='sources')
    op.drop_column('sources', 'secondary_themes')
