"""Recorder best-effort des appels API externes (Mistral / Brave).

Persiste une ligne dans `api_usage_events` par appel API externe. Reprend le
pattern de `_record_search_log` (smart_source_search) : session courte dédiée
via `safe_async_session`, jamais bloquant pour la transaction métier, ne lève
jamais. Gated par `settings.usage_tracking_enabled` (kill-switch, défaut on)
pour pouvoir couper toute l'instrumentation sans redéploiement de schéma.

Enabler observabilité scaling (WP-E) — cf.
docs/maintenance/maintenance-observabilite-scaling.md
"""

from __future__ import annotations

import time
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from uuid import UUID

import structlog

from app.config import get_settings
from app.database import safe_async_session
from app.models.api_usage_event import ApiUsageEvent

logger = structlog.get_logger()

# Call sites canoniques — à garder en phase avec les sites instrumentés. Une
# valeur hors set est tout de même enregistrée (on ne bloque jamais), mais
# émet un warning pour que les typos remontent dans les logs au lieu de
# polluer silencieusement les analytics.
CALL_SITES: frozenset[str] = frozenset(
    {
        "classification_pass1",  # mistral-small (classification_service)
        "good_news_pass2",  # mistral-large (good_news_classifier)
        "editorial",  # editorial llm_client (curation/pipeline/deep/perspective)
        "veille_suggester",  # mistral-medium (source/angle suggesters)
        "smart_search_mistral",  # mistral-small fallback (smart_source_search)
        "smart_search_brave",  # brave (smart_source_search)
    }
)

_VALID_STATUSES: frozenset[str] = frozenset({"ok", "error", "rate_limited"})


async def record_api_call(
    provider: str,
    call_site: str,
    *,
    model: str | None = None,
    user_id: UUID | str | None = None,
    status: str = "ok",
    latency_ms: int | None = None,
    prompt_tokens: int | None = None,
    completion_tokens: int | None = None,
) -> None:
    """Persiste un appel API externe dans `api_usage_events`.

    `prompt_tokens` / `completion_tokens` proviennent de `usage` Mistral quand
    disponible (None pour Brave ou un appel échoué avant réponse) — ils donnent
    le € réel par modèle via un `GROUP BY model` (LR-1 PR 1).

    Best-effort : ne lève jamais, ne bloque jamais la transaction métier
    (session courte dédiée). Désactivable d'un coup via le kill-switch
    `usage_tracking_enabled`.
    """
    if not get_settings().usage_tracking_enabled:
        return

    if call_site not in CALL_SITES:
        logger.warning("usage_recorder.unknown_call_site", call_site=call_site)

    uid: UUID | None
    if isinstance(user_id, str):
        try:
            uid = UUID(user_id)
        except (ValueError, AttributeError):
            uid = None
    else:
        uid = user_id

    try:
        async with safe_async_session() as session:
            session.add(
                ApiUsageEvent(
                    provider=provider[:16],
                    model=model[:48] if model else None,
                    call_site=call_site[:48],
                    user_id=uid,
                    status=status if status in _VALID_STATUSES else "ok",
                    latency_ms=latency_ms,
                    prompt_tokens=prompt_tokens,
                    completion_tokens=completion_tokens,
                )
            )
            await session.commit()
    except Exception as exc:  # noqa: BLE001 — l'instrumentation ne casse jamais l'appelant
        logger.warning(
            "usage_recorder.persist_failed",
            call_site=call_site,
            error=str(exc),
            exc_type=type(exc).__name__,
        )


class _ApiCallTracker:
    """État mutable d'un appel suivi par `track_api_call`.

    Défaut `error` : si le bloc sort sans avoir posé de statut (exception,
    timeout, `return` précoce), l'appel est compté comme échoué. Le bloc pose
    aussi `prompt_tokens` / `completion_tokens` depuis `usage` Mistral quand la
    réponse arrive ; ils restent None sinon (Brave, échec, provider sans usage).
    """

    __slots__ = ("status", "prompt_tokens", "completion_tokens")

    def __init__(self) -> None:
        self.status = "error"
        self.prompt_tokens: int | None = None
        self.completion_tokens: int | None = None


@asynccontextmanager
async def track_api_call(
    provider: str,
    call_site: str,
    *,
    model: str | None = None,
    user_id: UUID | str | None = None,
) -> AsyncIterator[_ApiCallTracker]:
    """Chronomètre un appel API externe et l'enregistre toujours en sortie.

    Remplace le boilerplate `t0` / `record_status` / `try-finally` répété sur
    chaque site instrumenté. Le bloc pose `tracker.status = "ok"` (ou
    `"rate_limited"`) ; sans pose explicite (exception, `return` précoce), le
    statut reste `error`. L'enregistrement (best-effort, jamais bloquant) a
    lieu dans le `finally`, y compris si le bloc lève — l'exception est ensuite
    propagée normalement.
    """
    t0 = time.monotonic()
    tracker = _ApiCallTracker()
    try:
        yield tracker
    finally:
        await record_api_call(
            provider=provider,
            call_site=call_site,
            model=model,
            user_id=user_id,
            status=tracker.status,
            latency_ms=int((time.monotonic() - t0) * 1000),
            prompt_tokens=tracker.prompt_tokens,
            completion_tokens=tracker.completion_tokens,
        )
