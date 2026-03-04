"""Tool agent : ecriture d'annotations de curation."""

import uuid
from datetime import datetime, timezone

from sqlalchemy import text

from admin.utils.db import get_connection

VALID_LABELS = ("good", "bad", "missing")

UPSERT_SQL = """
INSERT INTO curation_annotations (id, user_id, content_id, feed_date, label, note, annotated_by, created_at)
VALUES (:id, :user_id, :content_id, :feed_date, :label, :note, :annotated_by, :created_at)
ON CONFLICT ON CONSTRAINT uq_curation_user_content_date
DO UPDATE SET label = EXCLUDED.label, note = EXCLUDED.note
RETURNING id, label, note
"""


def write_annotation(
    user_id: str,
    content_id: str,
    feed_date: str,
    label: str,
    note: str | None = None,
    annotated_by: str = "agent",
) -> dict:
    """Insere ou met a jour une annotation de curation.

    Args:
        user_id: UUID de l'utilisateur.
        content_id: UUID du contenu.
        feed_date: Date du feed (YYYY-MM-DD).
        label: 'good', 'bad', ou 'missing'.
        note: Note optionnelle.
        annotated_by: Auteur de l'annotation (default: 'agent').

    Returns:
        Dictionnaire avec id, label, note de l'annotation.

    Raises:
        ValueError: Si le label est invalide.
    """
    if label not in VALID_LABELS:
        raise ValueError(f"Label invalide : {label}. Valeurs acceptees : {VALID_LABELS}")

    with get_connection() as conn:
        result = conn.execute(
            text(UPSERT_SQL),
            {
                "id": str(uuid.uuid4()),
                "user_id": user_id,
                "content_id": content_id,
                "feed_date": feed_date,
                "label": label,
                "note": note,
                "annotated_by": annotated_by,
                "created_at": datetime.now(timezone.utc).isoformat(),
            },
        )
        conn.commit()
        row = result.fetchone()
        return {"id": str(row[0]), "label": row[1], "note": row[2]}
