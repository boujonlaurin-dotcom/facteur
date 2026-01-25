"""fix user_personalization fk

Revision ID: 1a2b3c4d5e6f
Revises: a8da35e3c12b
Create Date: 2026-01-23 01:15:00.000000

SAFE MIGRATION PATTERN:
- Uses NOT VALID to add FK without full table scan (instant)
- Uses VALIDATE CONSTRAINT separately (non-blocking, SHARE UPDATE EXCLUSIVE lock)
- Avoids ACCESS EXCLUSIVE lock that blocks all operations

This fixes timeout issues with Supabase PgBouncer pooler.
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
    # SAFE FK MIGRATION PATTERN (non-blocking)
    # Step 1: Add new FK with NOT VALID (instant, no table scan)
    # This allows concurrent reads/writes during migration
    op.execute("""
        ALTER TABLE user_personalization 
        ADD CONSTRAINT user_personalization_user_id_fkey_new 
        FOREIGN KEY (user_id) REFERENCES user_profiles(user_id) 
        ON DELETE CASCADE 
        NOT VALID
    """)
    
    # Step 2: Drop the old FK (fast, new constraint already protects writes)
    op.execute("""
        ALTER TABLE user_personalization 
        DROP CONSTRAINT IF EXISTS user_personalization_user_id_fkey
    """)
    
    # Step 3: Rename new constraint to canonical name
    op.execute("""
        ALTER TABLE user_personalization 
        RENAME CONSTRAINT user_personalization_user_id_fkey_new 
        TO user_personalization_user_id_fkey
    """)
    
    # Step 4: Validate constraint (SHARE UPDATE EXCLUSIVE lock, allows concurrent DML)
    # This scans existing rows but doesn't block normal operations
    op.execute("""
        ALTER TABLE user_personalization 
        VALIDATE CONSTRAINT user_personalization_user_id_fkey
    """)


def downgrade() -> None:
    # Reverse: point FK back to user_profiles.id
    op.execute("""
        ALTER TABLE user_personalization 
        ADD CONSTRAINT user_personalization_user_id_fkey_old 
        FOREIGN KEY (user_id) REFERENCES user_profiles(id) 
        ON DELETE CASCADE 
        NOT VALID
    """)
    
    op.execute("""
        ALTER TABLE user_personalization 
        DROP CONSTRAINT IF EXISTS user_personalization_user_id_fkey
    """)
    
    op.execute("""
        ALTER TABLE user_personalization 
        RENAME CONSTRAINT user_personalization_user_id_fkey_old 
        TO user_personalization_user_id_fkey
    """)
    
    op.execute("""
        ALTER TABLE user_personalization 
        VALIDATE CONSTRAINT user_personalization_user_id_fkey
    """)
