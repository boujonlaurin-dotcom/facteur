"""add_content_entities

Revision ID: p1q2r3s4t5u6
Revises: z1a2b3c4d5e6
Create Date: 2026-01-30 18:45:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import ARRAY


from alembic import context
from sqlalchemy.exc import OperationalError
import time


# revision identifiers, used by Alembic.
revision: str = 'p1q2r3s4t5u6'
down_revision: Union[str, Sequence[str], None] = 'z1a2b3c4d5e6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _execute_with_retry(sql: str, retries: int = 30, sleep_seconds: int = 5) -> None:
    """Retry DDL when blocked by lock/statement timeouts."""
    for attempt in range(1, retries + 1):
        try:
            with context.get_context().autocommit_block():
                op.execute("SET lock_timeout = '5s'")
                op.execute("SET statement_timeout = '0'")
                op.execute(sql)
            return
        except OperationalError as exc:
            message = str(exc).lower()
            if "timeout" in message or "canceling statement" in message:
                if attempt >= retries:
                    raise
                time.sleep(sleep_seconds)
            else:
                raise


def upgrade() -> None:
    """Add entities column to contents table with GIN index."""
    # Step 1: Add column safely
    _execute_with_retry("ALTER TABLE contents ADD COLUMN IF NOT EXISTS entities TEXT[]")
    
    # Step 2: Create index safely
    _execute_with_retry("CREATE INDEX IF NOT EXISTS ix_contents_entities ON contents USING gin (entities)")


def downgrade() -> None:
    """Remove entities column and index from contents table."""
    op.execute("DROP INDEX IF EXISTS ix_contents_entities")
    op.execute("ALTER TABLE contents DROP COLUMN IF EXISTS entities")
