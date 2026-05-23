"""add language column to contents

PR 5 (LLM bias annotation, contrat enrichi). Stocke la langue détectée
du titre pour la section "Couverture étrangère" du panneau perspectives
(consommée par PR 6 mobile). Backfill heuristique via
`is_french_source` + `looks_english` ; les nouveaux contents sont
remplis à l'ingestion (sync_service.py).
"""

from collections.abc import Iterator

import sqlalchemy as sa

from alembic import op
from app.services.ml.language_filter import detect_language

revision: str = "lg01_add_language_to_contents"
down_revision: str | None = "23a4_restore_ct_favorites"
branch_labels: str | None = None
depends_on: str | None = None

_BATCH_SIZE = 500


def _iter_batches(bind, query: str) -> Iterator[list]:
    result = bind.execution_options(stream_results=True).execute(sa.text(query))
    batch: list = []
    for row in result:
        batch.append(row)
        if len(batch) >= _BATCH_SIZE:
            yield batch
            batch = []
    if batch:
        yield batch


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
    query = (
        "SELECT c.id, c.title, s.name AS source_name "
        "FROM contents c LEFT JOIN sources s ON s.id = c.source_id "
        "WHERE c.language IS NULL"
    )
    update_stmt = sa.text(
        "UPDATE contents SET language = :language WHERE id = :id"
    )
    for batch in _iter_batches(bind, query):
        updates = []
        for row in batch:
            lang = detect_language(row.title, row.source_name)
            if lang is None:
                continue
            updates.append({"id": row.id, "language": lang})
        if updates:
            bind.execute(update_stmt, updates)


def downgrade() -> None:
    op.drop_index("ix_contents_language", table_name="contents")
    op.drop_column("contents", "language")
