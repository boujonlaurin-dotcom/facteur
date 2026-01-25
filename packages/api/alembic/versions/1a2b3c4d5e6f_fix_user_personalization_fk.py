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
from sqlalchemy import text
from sqlalchemy.exc import OperationalError

# revision identifiers, used by Alembic.
revision = '1a2b3c4d5e6f'
down_revision = 'a8da35e3c12b'
branch_labels = None
depends_on = None


def _execute_with_retry(sql: str, retries: int = 30, sleep_seconds: int = 5) -> None:
    """Retry DDL when blocked by lock/statement timeouts.
    
    Uses AUTOCOMMIT so failed DDL does not abort the transaction.
    """
    conn = op.get_bind().execution_options(isolation_level="AUTOCOMMIT")
    for attempt in range(1, retries + 1):
        try:
            conn.execute(text("SET lock_timeout = '5s'"))
            conn.execute(text("SET statement_timeout = '0'"))
            conn.execute(text(sql))
            return
        except OperationalError as exc:
            message = str(exc).lower()
            if "timeout" in message or "canceling statement" in message:
                if attempt >= retries:
                    raise
                conn.execute(text(f"SELECT pg_sleep({sleep_seconds})"))
            else:
                raise


def upgrade() -> None:
    # Reduce lock contention during migration
    op.execute("SET LOCAL lock_timeout = '5s'")
    op.execute("SET LOCAL statement_timeout = '0'")  # Disable statement timeout for DDL
    
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
    
    # Step 2: Drop the old FK (may require lock; retry until window is free)
    _execute_with_retry("""
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
    # Reduce lock contention during migration
    op.execute("SET LOCAL lock_timeout = '5s'")
    op.execute("SET LOCAL statement_timeout = '0'")
    
    # Reverse: point FK back to user_profiles.id
    op.execute("""
        ALTER TABLE user_personalization 
        ADD CONSTRAINT user_personalization_user_id_fkey_old 
        FOREIGN KEY (user_id) REFERENCES user_profiles(id) 
        ON DELETE CASCADE 
        NOT VALID
    """)
    
    _execute_with_retry("""
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
