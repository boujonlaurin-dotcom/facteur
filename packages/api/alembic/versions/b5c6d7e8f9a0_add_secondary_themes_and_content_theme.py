"""add secondary_themes to sources and theme to contents

Revision ID: b5c6d7e8f9a0
Revises: a424896cdfd9
Create Date: 2026-02-12 12:00:00.000000

"""
from typing import Sequence, Union

from alembic import op

# revision identifiers, used by Alembic.
revision: str = 'b5c6d7e8f9a0'
down_revision: Union[str, None] = 'a424896cdfd9'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # SET LOCAL in env.py disables statement_timeout for all migrations.
    # IF NOT EXISTS ensures idempotency across Dockerfile retry attempts.

    # Phase 1: secondary_themes on sources
    op.execute(
        "ALTER TABLE sources ADD COLUMN IF NOT EXISTS secondary_themes TEXT[]"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_sources_secondary_themes "
        "ON sources USING gin (secondary_themes)"
    )

    # Phase 2: theme on contents
    op.execute(
        "ALTER TABLE contents ADD COLUMN IF NOT EXISTS theme VARCHAR(50)"
    )
    op.execute(
        "CREATE INDEX IF NOT EXISTS ix_contents_theme ON contents (theme)"
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_contents_theme")
    op.execute("ALTER TABLE contents DROP COLUMN IF EXISTS theme")
    op.execute("DROP INDEX IF EXISTS ix_sources_secondary_themes")
    op.execute("ALTER TABLE sources DROP COLUMN IF EXISTS secondary_themes")
