"""baseline — prod schema snapshot 2026-04-30.

Brownfield baseline. Replaces the 74 pre-existing migrations (now in `_archive/`)
which had drifted from prod due to manual SQL applied via Supabase SQL Editor
and `--autogenerate` runs against drifted DBs.

The SQL in `baseline/prod-schema-2026-04-30.sql` is a sanitized
`pg_dump --schema-only --schema=public` snapshot of prod taken on 2026-04-30.

On prod, this revision is applied via `alembic stamp 00000_baseline` (no schema
change). On a fresh local DB, `alembic upgrade head` runs the SQL to rebuild
prod's schema.

See `docs/maintenance/maintenance-alembic-baseline-squash.md` for context.
"""
from pathlib import Path

from alembic import op


revision: str = "00000_baseline"
down_revision: str | None = None
branch_labels: str | None = None
depends_on: str | None = None


_BASELINE_SQL_PATH = (
    Path(__file__).resolve().parent.parent / "baseline" / "prod-schema-2026-04-30.sql"
)


def upgrade() -> None:
    sql = _BASELINE_SQL_PATH.read_text()
    op.execute(sql)


def downgrade() -> None:
    raise NotImplementedError(
        "baseline migration is not reversible — restore from a Supabase backup instead"
    )
