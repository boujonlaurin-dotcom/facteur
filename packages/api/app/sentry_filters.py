"""Filtres d'événements Sentry indépendants du démarrage FastAPI."""

import re

_SESSION_TIMEOUT_SQL_RE = re.compile(
    r"^SET LOCAL (?:statement_timeout|idle_in_transaction_session_timeout) = \d+$"
)


def before_send_transaction(event: dict, hint: dict) -> dict:
    """Retire les spans SQL d'armement des timeout de session uniquement.

    `safe_async_session` et `get_db` émettent ces deux commandes à chaque
    session courte pour prévenir les transactions zombies. Elles sont répétées
    par conception, mais font déclencher le détecteur N+1 de Sentry sans être
    du travail métier. La transaction, sa durée et tous les autres spans sont
    conservés pour le suivi de performance de `/api/feed/`.
    """
    spans = event.get("spans")
    if not isinstance(spans, list):
        return event
    event["spans"] = [
        span
        for span in spans
        if not _SESSION_TIMEOUT_SQL_RE.fullmatch(
            str(span.get("description", "")).strip()
        )
    ]
    return event
