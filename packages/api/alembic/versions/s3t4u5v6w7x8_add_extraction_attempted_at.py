"""add extraction_attempted_at column to contents

Revision ID: s3t4u5v6w7x8
Revises: r2s3t4u5v6w7
Create Date: 2026-02-27 21:00:00.000000

Prevents infinite extraction retries by tracking when the last attempt occurred.
On-demand enrichment skips articles with a recent attempt (cooldown 6h).
"""
from typing import Sequence, Union

from alembic import op, context
from sqlalchemy.exc import OperationalError
import time

# revision identifiers, used by Alembic.
revision: str = 's3t4u5v6w7x8'
down_revision: Union[str, None] = 'r2s3t4u5v6w7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _execute_with_retry(sql: str, retries: int = 5, sleep_seconds: int = 5, lock_timeout: str = '5s') -> None:
    """Retry DDL when blocked by lock/statement timeouts (PgBouncer-safe)."""
    escaped_sql = sql.replace("'", "''")

    for attempt in range(1, retries + 1):
        try:
            with context.get_context().autocommit_block():
                op.execute(
                    f"DO $mig$ BEGIN "
                    f"PERFORM set_config('lock_timeout', '{lock_timeout}', true); "
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
    print("[migration] Starting s3t4u5v6w7x8: add extraction_attempted_at...", flush=True)

    _execute_with_retry(
        "ALTER TABLE contents "
        "ADD COLUMN IF NOT EXISTS extraction_attempted_at TIMESTAMPTZ DEFAULT NULL",
        lock_timeout='30s'
    )

    print("[migration] s3t4u5v6w7x8 complete", flush=True)


def downgrade() -> None:
    op.drop_column('contents', 'extraction_attempted_at')
