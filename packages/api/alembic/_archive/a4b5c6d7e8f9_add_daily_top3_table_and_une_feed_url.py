"""add_daily_top3_table_and_une_feed_url

Revision ID: a4b5c6d7e8f9
Revises: k8l9m0n1o2p3
Create Date: 2026-01-19 23:10:00.000000

Story 4.4: Top 3 Briefing Quotidien
- Crée la table daily_top3 pour stocker les briefings quotidiens
- Ajoute le champ une_feed_url sur sources pour les feeds "À la Une"
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = 'a4b5c6d7e8f9'
down_revision: Union[str, Sequence[str], None] = 'k8l9m0n1o2p3'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    # 1. Créer la table daily_top3
    op.create_table(
        'daily_top3',
        sa.Column('id', postgresql.UUID(as_uuid=True), nullable=False, server_default=sa.text('uuid_generate_v4()')),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('content_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('rank', sa.Integer(), nullable=False),
        sa.Column('top3_reason', sa.String(length=100), nullable=False),
        sa.Column('consumed', sa.Boolean(), server_default='false', nullable=False),
        sa.Column('generated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.CheckConstraint('rank >= 1 AND rank <= 3', name='ck_daily_top3_rank_range'),
        sa.ForeignKeyConstraint(['content_id'], ['contents.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id')
    )
    
    # Index pour requêtes par user et date
    op.create_index('ix_daily_top3_user_id', 'daily_top3', ['user_id'], unique=False)
    op.create_index('ix_daily_top3_user_date', 'daily_top3', ['user_id', 'generated_at'], unique=False)
    
    # 2. Ajouter le champ une_feed_url sur sources
    op.add_column('sources', sa.Column('une_feed_url', sa.Text(), nullable=True))


def downgrade() -> None:
    """Downgrade schema."""
    # Supprimer le champ une_feed_url
    op.drop_column('sources', 'une_feed_url')
    
    # Supprimer les index et la table daily_top3
    op.drop_index('ix_daily_top3_user_date', table_name='daily_top3')
    op.drop_index('ix_daily_top3_user_id', table_name='daily_top3')
    op.drop_table('daily_top3')
