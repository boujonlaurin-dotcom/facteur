"""add content_quality column to contents

Revision ID: r2s3t4u5v6w7
Revises: x8y9z0a1b2c3
Create Date: 2026-02-27 12:00:00.000000

Adds content_quality column for in-app reading quality signal:
- 'full': content > 500 chars (suitable for in-app reading)
- 'partial': 100-500 chars (preview with CTA)
- 'none': < 100 chars or missing
"""
from typing import Sequence, Union

from alembic import op, context
from sqlalchemy.exc import OperationalError
import time

# revision identifiers, used by Alembic.
revision: str = 'r2s3t4u5v6w7'
down_revision: Union[str, None] = 'x8y9z0a1b2c3'
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
    print("[migration] Starting r2s3t4u5v6w7: add content_quality...", flush=True)

    _execute_with_retry(
        "ALTER TABLE contents "
        "ADD COLUMN IF NOT EXISTS content_quality VARCHAR(20) DEFAULT NULL",
        lock_timeout='30s'
    )

    print("[migration] r2s3t4u5v6w7 complete", flush=True)


def downgrade() -> None:
    op.drop_column('contents', 'content_quality')
