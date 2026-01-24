"""fix user_personalization fk

Revision ID: 1a2b3c4d5e6f
Revises: f7e8a9b0c1d2
Create Date: 2026-01-23 01:15:00.000000

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = '1a2b3c4d5e6f'
down_revision = 'a8da35e3c12b'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("SET LOCAL statement_timeout = '5min'")
    # 1. Drop existing FK
    # We need the constraint name. Usually it's user_personalization_user_id_fkey
    op.drop_constraint('user_personalization_user_id_fkey', 'user_personalization', type_='foreignkey')
    
    # 2. Add new FK to user_profiles.user_id
    op.create_foreign_key(
        'user_personalization_user_id_fkey',
        'user_personalization',
        'user_profiles',
        ['user_id'],
        ['user_id'],
        ondelete='CASCADE'
    )


def downgrade() -> None:
    op.execute("SET LOCAL statement_timeout = '5min'")
    op.drop_constraint('user_personalization_user_id_fkey', 'user_personalization', type_='foreignkey')
    op.create_foreign_key(
        'user_personalization_user_id_fkey',
        'user_personalization',
        'user_profiles',
        ['user_id'],
        ['id'],
        ondelete='CASCADE'
    )
