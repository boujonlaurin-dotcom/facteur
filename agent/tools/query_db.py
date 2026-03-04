"""Tool agent : execution SQL read-only."""

from sqlalchemy import text

from admin.utils.db import get_connection

FORBIDDEN_KEYWORDS = frozenset([
    "INSERT", "UPDATE", "DELETE", "DROP", "ALTER",
    "CREATE", "TRUNCATE", "GRANT", "REVOKE",
])


def query_db(sql: str, params: dict | None = None) -> list[dict]:
    """Execute une requete SQL read-only et retourne les resultats.

    Args:
        sql: Requete SELECT avec named params (:param_name).
        params: Dictionnaire de parametres nommes.

    Returns:
        Liste de dictionnaires (une entree par ligne).

    Raises:
        ValueError: Si la requete contient des mots-cles interdits.
    """
    # Validation read-only
    normalized = sql.upper().strip()
    for kw in FORBIDDEN_KEYWORDS:
        # Check as whole word to avoid false positives (e.g., "CREATED_AT")
        if f" {kw} " in f" {normalized} ":
            raise ValueError(f"Mot-cle SQL interdit : {kw}. Seules les requetes SELECT sont autorisees.")

    with get_connection() as conn:
        result = conn.execute(text(sql), params or {})
        columns = list(result.keys())
        rows = []
        for row in result.fetchall():
            row_dict = {}
            for i, col in enumerate(columns):
                val = row[i]
                # Convert non-serializable types to strings
                if hasattr(val, "isoformat"):
                    val = val.isoformat()
                elif hasattr(val, "hex"):
                    val = str(val)
                row_dict[col] = val
            rows.append(row_dict)
        return rows
