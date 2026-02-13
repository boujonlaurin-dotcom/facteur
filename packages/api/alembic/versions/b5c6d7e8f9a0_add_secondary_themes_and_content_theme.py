"""add secondary_themes to sources and theme to contents

Revision ID: b5c6d7e8f9a0
Revises: a424896cdfd9
Create Date: 2026-02-12 12:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
from alembic import context
from sqlalchemy.exc import OperationalError
import time

# revision identifiers, used by Alembic.
revision: str = 'b5c6d7e8f9a0'
down_revision: Union[str, None] = 'a424896cdfd9'
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
    # Phase 1: secondary_themes on sources
    _execute_with_retry(
        "ALTER TABLE sources ADD COLUMN IF NOT EXISTS secondary_themes TEXT[]"
    )
    _execute_with_retry(
        "CREATE INDEX IF NOT EXISTS ix_sources_secondary_themes "
        "ON sources USING gin (secondary_themes)"
    )

    # Phase 2: theme on contents
    _execute_with_retry(
        "ALTER TABLE contents ADD COLUMN IF NOT EXISTS theme VARCHAR(50)"
    )
    _execute_with_retry(
        "CREATE INDEX IF NOT EXISTS ix_contents_theme ON contents (theme)"
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_contents_theme")
    op.execute("ALTER TABLE contents DROP COLUMN IF EXISTS theme")
    op.execute("DROP INDEX IF EXISTS ix_sources_secondary_themes")
    op.execute("ALTER TABLE sources DROP COLUMN IF EXISTS secondary_themes")
