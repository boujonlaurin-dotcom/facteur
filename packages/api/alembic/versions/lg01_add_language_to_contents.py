"""add language column to contents

PR 5 (LLM bias annotation, contrat enrichi). Stocke la langue détectée
du titre pour la section "Couverture étrangère" du panneau perspectives
(consommée par PR 6 mobile). Backfill heuristique via
`is_french_source` + `looks_english` ; les nouveaux contents sont
remplis à l'ingestion (sync_service.py).
"""

import sqlalchemy as sa

from alembic import op
from app.services.ml.language_filter import detect_language

revision: str = "lg01_add_language_to_contents"
down_revision: str | None = "23a4_restore_ct_favorites"
branch_labels: str | None = None
depends_on: str | None = None

_BATCH_SIZE = 500


def upgrade() -> None:
    op.add_column(
        "contents",
        sa.Column("language", sa.String(length=8), nullable=True),
    )
    op.create_index("ix_contents_language", "contents", ["language"])

    # Offline mode (`alembic upgrade --sql`) has no live connection — emit
    # the DDL only, skip the Python-driven backfill.
    if op.get_context().as_sql:
        return

    bind = op.get_bind()

    # Fetch all rows to backfill in one query, then slice in Python.
    # Avoids server-side cursors (stream_results=True) which leak cursor state
    # in psycopg3 async — causing Alembic's subsequent UPDATE alembic_version
    # to be wrapped in DECLARE CURSOR FOR UPDATE → SyntaxError PostgreSQL.
    # Keyset pagination (id > :last_id) is also unsuitable because c.id is UUID
    # and the initial sentinel 0 (smallint) triggers "operator does not exist:
    # uuid > smallint". A single fetchall() is simpler and safe for a one-time
    # migration where the result set fits in memory.
    rows = bind.execute(
        sa.text(
            "SELECT c.id, c.title, s.name AS source_name "
            "FROM contents c LEFT JOIN sources s ON s.id = c.source_id "
            "WHERE c.language IS NULL"
        )
    ).fetchall()

    update_stmt = sa.text(
        "UPDATE contents SET language = :language WHERE id = :id"
    )
    for i in range(0, len(rows), _BATCH_SIZE):
        batch = rows[i : i + _BATCH_SIZE]
        updates = [
            {"id": row.id, "language": lang}
            for row in batch
            if (lang := detect_language(row.title, row.source_name)) is not None
        ]
        if updates:
            bind.execute(update_stmt, updates)


def downgrade() -> None:
    op.drop_index("ix_contents_language", table_name="contents")
    op.drop_column("contents", "language")
