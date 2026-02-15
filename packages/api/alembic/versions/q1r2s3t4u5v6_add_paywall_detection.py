"""add paywall detection columns

Revision ID: q1r2s3t4u5v6
Revises: d7e8f9a0b1c2
Create Date: 2026-02-15 12:00:00.000000

Adds paywall detection support:
- sources.paywall_config JSONB for per-source paywall patterns
- contents.is_paid BOOLEAN for detected paywall articles
- user_personalization.hide_paid_content BOOLEAN for user preference
"""
from typing import Sequence, Union

from alembic import op
from alembic import context
from sqlalchemy.exc import OperationalError
import time

# revision identifiers, used by Alembic.
revision: str = 'q1r2s3t4u5v6'
down_revision: Union[str, None] = 'd7e8f9a0b1c2'
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
    print("[migration] Starting q1r2s3t4u5v6: add paywall detection...", flush=True)

    # 1. sources.paywall_config - per-source paywall detection patterns
    # NULL means "use DEFAULT_PAYWALL_CONFIG" in PaywallDetector
    _execute_with_retry(
        "ALTER TABLE sources "
        "ADD COLUMN IF NOT EXISTS paywall_config JSONB DEFAULT NULL"
    )

    # 2. contents.is_paid - whether article is behind a paywall
    _execute_with_retry(
        "ALTER TABLE contents "
        "ADD COLUMN IF NOT EXISTS is_paid BOOLEAN DEFAULT false"
    )

    # 3. user_personalization.hide_paid_content - user toggle
    _execute_with_retry(
        "ALTER TABLE user_personalization "
        "ADD COLUMN IF NOT EXISTS hide_paid_content BOOLEAN DEFAULT true"
    )

    print("[migration] q1r2s3t4u5v6 complete", flush=True)


def downgrade() -> None:
    op.drop_column('user_personalization', 'hide_paid_content')
    op.drop_column('contents', 'is_paid')
    op.drop_column('sources', 'paywall_config')
