"""replace ix_contents_theme with composite ix_contents_theme_published

Revision ID: f1e2d3c4b5a6
Revises: q1r2s3t4u5v6
Create Date: 2026-02-16 12:00:00.000000

Replaces single-column ix_contents_theme with composite (theme, published_at DESC)
to optimize theme-filtered feed queries that ORDER BY published_at DESC.
The composite index is a strict superset of the single-column index.
"""
from typing import Sequence, Union

from alembic import op
from alembic import context
from sqlalchemy.exc import OperationalError
import time

# revision identifiers, used by Alembic.
revision: str = 'f1e2d3c4b5a6'
down_revision: Union[str, None] = 'q1r2s3t4u5v6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _execute_with_retry(sql: str, retries: int = 5, sleep_seconds: int = 5) -> None:
    """Retry DDL when blocked by lock/statement timeouts.

    Uses a DO block to ensure SET + DDL run on the same backend connection,
    even through PgBouncer transaction-mode pooling.
    """
    escaped_sql = sql.replace("'", "''")

    for attempt in range(1, retries + 1):
        try:
            with context.get_context().autocommit_block():
                op.execute(
                    f"DO $mig$ BEGIN "
                    f"PERFORM set_config('lock_timeout', '5s', true); "
                    f"PERFORM set_config('statement_timeout', '0', true); "
                    f"EXECUTE '{escaped_sql}'; "
                    f"END $mig$;"
                )
            print(f"[migration] OK (attempt {attempt}): {sql[:80]}", flush=True)
            return
        except OperationalError as exc:
            message = str(exc).lower()
            if "timeout" in message or "canceling statement" in message or "lock" in message:
                print(f"[migration] blocked (attempt {attempt}/{retries}): {sql[:80]}", flush=True)
                if attempt >= retries:
                    raise
                time.sleep(sleep_seconds)
            else:
                raise


def upgrade() -> None:
    print("[migration] Starting f1e2d3c4b5a6: replace theme index with composite...", flush=True)

    # Phase 1: Create new composite index
    _execute_with_retry(
        "CREATE INDEX IF NOT EXISTS ix_contents_theme_published "
        "ON contents (theme, published_at DESC)"
    )

    # Phase 2: Drop old single-column index (superseded by composite)
    _execute_with_retry(
        "DROP INDEX IF EXISTS ix_contents_theme"
    )

    print("[migration] f1e2d3c4b5a6 complete", flush=True)


def downgrade() -> None:
    # Restore original single-column index
    _execute_with_retry(
        "CREATE INDEX IF NOT EXISTS ix_contents_theme ON contents (theme)"
    )
    _execute_with_retry(
        "DROP INDEX IF EXISTS ix_contents_theme_published"
    )
