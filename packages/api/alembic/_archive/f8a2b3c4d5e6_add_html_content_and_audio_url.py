"""add_html_content_and_audio_url_to_content

Revision ID: f8a2b3c4d5e6
Revises: ce8cff0c3c5d
Create Date: 2026-01-17 10:30:00.000000

Story 5.2: In-App Reading Mode - Add fields for native content display
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'f8a2b3c4d5e6'
down_revision: Union[str, Sequence[str], None] = 'ce8cff0c3c5d'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    # Story 5.2: In-App Reading Mode
    # html_content: Stores content:encoded from RSS for articles
    # audio_url: Stores enclosure URL for podcasts
    op.add_column('contents', sa.Column('html_content', sa.Text(), nullable=True))
    op.add_column('contents', sa.Column('audio_url', sa.Text(), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_column('contents', 'audio_url')
    op.drop_column('contents', 'html_content')
