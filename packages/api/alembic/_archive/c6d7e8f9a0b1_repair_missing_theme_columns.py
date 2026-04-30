"""repair: ensure contents.theme and sources.secondary_themes columns exist

Revision ID: c6d7e8f9a0b1
Revises: b5c6d7e8f9a0
Create Date: 2026-02-13 22:00:00.000000

Migration b5c6d7e8f9a0 was marked as applied in alembic_version but the DDL
may not have executed due to PgBouncer transaction-mode timeouts during the
initial deployment. This repair migration uses IF NOT EXISTS to safely add
the missing columns without failing if they already exist.
"""
from typing import Sequence, Union

from alembic import op
from alembic import context
from sqlalchemy.exc import OperationalError
import time

# revision identifiers, used by Alembic.
revision: str = 'c6d7e8f9a0b1'
down_revision: Union[str, None] = 'b5c6d7e8f9a0'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _execute_with_retry(sql: str, retries: int = 30, sleep_seconds: int = 5) -> None:
    """Retry DDL when blocked by lock/statement timeouts (PgBouncer-safe)."""
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
    print("[migration] Starting c6d7e8f9a0b1 repair...", flush=True)

    # Repair: sources.secondary_themes (from b5c6d7e8f9a0)
    _execute_with_retry(
        "ALTER TABLE sources ADD COLUMN IF NOT EXISTS secondary_themes TEXT[]"
    )
    _execute_with_retry(
        "CREATE INDEX IF NOT EXISTS ix_sources_secondary_themes "
        "ON sources USING gin (secondary_themes)"
    )

    # Repair: contents.theme (from b5c6d7e8f9a0)
    _execute_with_retry(
        "ALTER TABLE contents ADD COLUMN IF NOT EXISTS theme VARCHAR(50)"
    )
    _execute_with_retry(
        "CREATE INDEX IF NOT EXISTS ix_contents_theme ON contents (theme)"
    )

    print("[migration] c6d7e8f9a0b1 repair complete", flush=True)


def downgrade() -> None:
    # No-op: don't remove columns that may have been created by original migration
    pass
