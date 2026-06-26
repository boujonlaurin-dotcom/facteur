"""Mistral LLM client for editorial pipeline via httpx.

Uses mistral-large-latest (most capable model) for editorial curation.
Reuses the existing MISTRAL_API_KEY from classification_service.
"""

from __future__ import annotations

import asyncio
import json

import httpx
import structlog

from app.config import get_settings
from app.services.editorial.rate_limiter import _MistralRateLimiter
from app.services.observability.usage_recorder import _ApiCallTracker, track_api_call

logger = structlog.get_logger()

MISTRAL_API_URL = "https://api.mistral.ai/v1/chat/completions"

# Politique de retry partagée par chat_json / chat_text (LR-1 PR 1).
_MISTRAL_RETRYABLE_STATUSES = (429, 500, 502, 503)
_MISTRAL_MAX_RETRIES = 2


# Limiteur partagé au niveau process (LR-1 PR 1). `EditorialLLMClient` étant
# instancié par appelant, un limiteur par instance ne bornerait pas l'agrégat
# du burst quotidien — il doit être un singleton module. Construit paresseusement
# pour lire les settings courants (et être recréable en test via _reset).
_large_limiter: _MistralRateLimiter | None = None


def _get_large_limiter() -> _MistralRateLimiter:
    global _large_limiter
    if _large_limiter is None:
        settings = get_settings()
        _large_limiter = _MistralRateLimiter(
            rpm=settings.mistral_large_rpm,
            concurrency=settings.mistral_large_concurrency,
        )
    return _large_limiter


def _reset_large_limiter() -> None:
    """Réinitialise le singleton (hook de test : bucket plein à chaque cas)."""
    global _large_limiter
    _large_limiter = None


def _is_large_model(model: str | None) -> bool:
    """True pour les modèles Mistral `large` (`mistral-large-*`).

    Le throttle ne cible que les appels `large` passant par `EditorialLLMClient`
    (curation + deep + perspective) : c'est la source dominante et *mesurée* des
    429 (cf. docstring du module rate_limiter). `good_news_classifier` appelle
    aussi un modèle `large`, mais via son propre client et en un seul appel
    batché par lot (burst négligeable) — hors scope de ce throttle pour LR-1
    PR 1 ; il pourra rejoindre un limiteur partagé en LR-3/PR 4.
    """
    return bool(model and "large" in model.lower())


class EditorialLLMClient:
    """Async Mistral client for editorial pipeline."""

    def __init__(self) -> None:
        settings = get_settings()
        self._api_key = settings.mistral_api_key
        self._ready = bool(self._api_key)
        self._client: httpx.AsyncClient | None = None

        if not self._ready:
            logger.warning(
                "editorial_llm.no_api_key",
                message="MISTRAL_API_KEY not set. Editorial pipeline unavailable.",
            )

    @property
    def is_ready(self) -> bool:
        return self._ready

    def _get_client(self) -> httpx.AsyncClient:
        if self._client is None:
            self._client = httpx.AsyncClient(
                timeout=30.0,
                headers={
                    "Authorization": f"Bearer {self._api_key}",
                    "Content-Type": "application/json",
                },
            )
        return self._client

    async def _do_post(self, payload: dict, model: str) -> httpx.Response:
        """POST Mistral, chokepoint unique du throttle large (LR-1 PR 1).

        Les appels `large` (curation/deep/perspective, source du burst 429) sont
        bornés par le limiteur partagé (token-bucket /minute + cap de
        concurrence) ; les modèles non-large passent directement. Chaque
        tentative (y compris un retry) repasse par le limiteur, donc les retries
        respectent aussi le débit au lieu de re-burster.
        """
        client = self._get_client()
        settings = get_settings()
        if settings.mistral_rate_limit_enabled and _is_large_model(model):
            async with _get_large_limiter().slot():
                return await client.post(MISTRAL_API_URL, json=payload)
        return await client.post(MISTRAL_API_URL, json=payload)

    async def _post_with_retry(
        self,
        payload: dict,
        model: str,
        tracker: _ApiCallTracker,
        *,
        event_prefix: str,
        unexpected_event: str,
    ) -> tuple[httpx.Response, int] | None:
        """POST + retry/backoff partagé par chat_json et chat_text (LR-1 PR 1).

        Renvoie `(réponse, n° de tentative)` au premier HTTP 2xx, ou `None` quand
        les retries sont épuisés / erreur non-retryable / timeout / exception
        inattendue. Pose `tracker.status = "rate_limited"` sur 429. Le parsing de
        la réponse, la capture des tokens, le log de succès et `status = "ok"`
        restent côté appelant : les deux méthodes ont des formes de réponse
        différentes, et un 200 au corps illisible doit rester un échec (le statut
        ne passe `ok` qu'après un parse réussi).

        Retryable : 429/500/502/503 + timeout, backoff 3s puis 6s. Les noms
        d'évènements de log diffèrent entre les deux méthodes (clés
        d'observabilité existantes) et sont donc paramétrés.
        """
        for attempt in range(_MISTRAL_MAX_RETRIES + 1):
            try:
                response = await self._do_post(payload, model)
                response.raise_for_status()
                return response, attempt
            except httpx.HTTPStatusError as e:
                if e.response.status_code == 429:
                    tracker.status = "rate_limited"
                if (
                    e.response.status_code in _MISTRAL_RETRYABLE_STATUSES
                    and attempt < _MISTRAL_MAX_RETRIES
                ):
                    wait = 3 * (attempt + 1)  # 3s, 6s
                    logger.warning(
                        f"editorial_llm.{event_prefix}retrying",
                        attempt=attempt + 1,
                        wait_s=wait,
                        status_code=e.response.status_code,
                    )
                    await asyncio.sleep(wait)
                    continue
                logger.error(
                    "editorial_llm.http_error",
                    status_code=e.response.status_code,
                    body=e.response.text[:500],
                    attempts_exhausted=attempt + 1,
                )
                return None
            except httpx.TimeoutException:
                if attempt < _MISTRAL_MAX_RETRIES:
                    wait = 3 * (attempt + 1)
                    logger.warning(
                        f"editorial_llm.{event_prefix}timeout_retrying",
                        attempt=attempt + 1,
                        wait_s=wait,
                    )
                    await asyncio.sleep(wait)
                    continue
                logger.error(
                    f"editorial_llm.{event_prefix}timeout_exhausted",
                    attempts_exhausted=attempt + 1,
                )
                return None
            except Exception as e:
                logger.error(unexpected_event, error=str(e))
                return None
        return None

    async def chat_json(
        self,
        system: str,
        user_message: str,
        model: str = "mistral-large-latest",
        temperature: float = 0.3,
        max_tokens: int = 1000,
        *,
        call_site: str = "editorial",
    ) -> dict | list | None:
        """Send a message to Mistral and parse JSON response.

        Returns parsed JSON (dict or list) on success, None on failure.

        `call_site` is the single chokepoint label propagated to
        `api_usage_events` — callers passing through this client override it
        (e.g. "veille_suggester", "smart_search_mistral"); default "editorial"
        covers curation/pipeline/deep/perspective.
        """
        if not self._ready:
            logger.warning("editorial_llm.not_ready")
            return None

        payload = {
            "model": model,
            "temperature": temperature,
            "max_tokens": max_tokens,
            "response_format": {"type": "json_object"},
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user_message},
            ],
        }

        async with track_api_call("mistral", call_site, model=model) as _call:
            result = await self._post_with_retry(
                payload,
                model,
                _call,
                event_prefix="",
                unexpected_event="editorial_llm.unexpected_error",
            )
            if result is None:
                return None
            response, attempt = result

            try:
                data = response.json()
                usage = data.get("usage") or {}
                _call.prompt_tokens = usage.get("prompt_tokens")
                _call.completion_tokens = usage.get("completion_tokens")
                text = data["choices"][0]["message"]["content"]

                # Strip markdown code fences if present
                text = text.strip()
                if text.startswith("```"):
                    lines = text.split("\n")
                    text = "\n".join(
                        lines[1:-1] if lines[-1].strip() == "```" else lines[1:]
                    )
                    text = text.strip()

                parsed = json.loads(text)

                logger.info(
                    "editorial_llm.success",
                    model=model,
                    attempt=attempt + 1,
                    prompt_tokens=usage.get("prompt_tokens"),
                    completion_tokens=usage.get("completion_tokens"),
                )
                _call.status = "ok"
                return parsed

            except json.JSONDecodeError as e:
                # No retry for parse errors — LLM returned bad JSON
                logger.error(
                    "editorial_llm.json_parse_error",
                    error=str(e),
                    raw_text=text[:500] if "text" in dir() else "no_text",
                )
                return None
            except Exception as e:
                logger.error("editorial_llm.unexpected_error", error=str(e))
                return None

    async def chat_text(
        self,
        system: str,
        user_message: str,
        model: str = "mistral-large-latest",
        temperature: float = 0.4,
        max_tokens: int = 300,
        *,
        call_site: str = "editorial",
    ) -> str | None:
        """Send a message to Mistral and return plain text response.

        Returns raw text string on success, None on failure. See `chat_json`
        for `call_site` semantics (single chokepoint label for usage tracking).
        """
        if not self._ready:
            logger.warning("editorial_llm.not_ready")
            return None

        payload = {
            "model": model,
            "temperature": temperature,
            "max_tokens": max_tokens,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user_message},
            ],
        }

        async with track_api_call("mistral", call_site, model=model) as _call:
            result = await self._post_with_retry(
                payload,
                model,
                _call,
                event_prefix="chat_text_",
                unexpected_event="editorial_llm.chat_text_error",
            )
            if result is None:
                return None
            response, attempt = result

            try:
                data = response.json()
                usage = data.get("usage") or {}
                _call.prompt_tokens = usage.get("prompt_tokens")
                _call.completion_tokens = usage.get("completion_tokens")
                text = data["choices"][0]["message"]["content"].strip()

                logger.info(
                    "editorial_llm.chat_text_success",
                    model=model,
                    attempt=attempt + 1,
                    prompt_tokens=usage.get("prompt_tokens"),
                    completion_tokens=usage.get("completion_tokens"),
                )
                _call.status = "ok"
                return text

            except Exception as e:
                logger.error("editorial_llm.chat_text_error", error=str(e))
                return None

    async def close(self) -> None:
        """Close the underlying httpx client."""
        if self._client:
            await self._client.aclose()
            self._client = None
