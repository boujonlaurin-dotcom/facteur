"""add_impression_fields

Revision ID: b2c3d4e5f6a7
Revises: z1a2b3c4d5e6
Create Date: 2026-02-24 10:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
from alembic import context
from sqlalchemy.exc import OperationalError
import time


# revision identifiers, used by Alembic.
revision: str = 'b2c3d4e5f6a7'
down_revision: Union[str, Sequence[str], None] = 'z1a2b3c4d5e6'
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
    """Add last_impressed_at and manually_impressed to user_content_status."""
    print("[migration] Starting b2c3d4e5f6a7: add impression fields...", flush=True)

    _execute_with_retry(
        "ALTER TABLE user_content_status "
        "ADD COLUMN IF NOT EXISTS last_impressed_at TIMESTAMPTZ DEFAULT NULL",
        lock_timeout='30s'
    )

    _execute_with_retry(
        "ALTER TABLE user_content_status "
        "ADD COLUMN IF NOT EXISTS manually_impressed BOOLEAN NOT NULL DEFAULT false",
        lock_timeout='30s'
    )

    print("[migration] b2c3d4e5f6a7 complete", flush=True)


def downgrade() -> None:
    """Remove impression fields."""
    op.drop_column('user_content_status', 'manually_impressed')
    op.drop_column('user_content_status', 'last_impressed_at')
