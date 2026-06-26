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
from app.services.observability.usage_recorder import track_api_call

logger = structlog.get_logger()

MISTRAL_API_URL = "https://api.mistral.ai/v1/chat/completions"


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
    """True pour les modèles `large` (les seuls bursty / rate-limited)."""
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

        _RETRYABLE_STATUSES = (429, 500, 502, 503)
        max_retries = 2

        async with track_api_call("mistral", call_site, model=model) as _call:
            for attempt in range(max_retries + 1):
                try:
                    response = await self._do_post(payload, model)
                    response.raise_for_status()

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

                except httpx.HTTPStatusError as e:
                    if e.response.status_code == 429:
                        _call.status = "rate_limited"
                    if (
                        e.response.status_code in _RETRYABLE_STATUSES
                        and attempt < max_retries
                    ):
                        wait = 3 * (attempt + 1)  # 3s, 6s
                        logger.warning(
                            "editorial_llm.retrying",
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
                    if attempt < max_retries:
                        wait = 3 * (attempt + 1)
                        logger.warning(
                            "editorial_llm.timeout_retrying",
                            attempt=attempt + 1,
                            wait_s=wait,
                        )
                        await asyncio.sleep(wait)
                        continue
                    logger.error(
                        "editorial_llm.timeout_exhausted",
                        attempts_exhausted=attempt + 1,
                    )
                    return None
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

        _RETRYABLE_STATUSES = (429, 500, 502, 503)
        max_retries = 2

        async with track_api_call("mistral", call_site, model=model) as _call:
            for attempt in range(max_retries + 1):
                try:
                    response = await self._do_post(payload, model)
                    response.raise_for_status()

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

                except httpx.HTTPStatusError as e:
                    if e.response.status_code == 429:
                        _call.status = "rate_limited"
                    if (
                        e.response.status_code in _RETRYABLE_STATUSES
                        and attempt < max_retries
                    ):
                        wait = 3 * (attempt + 1)  # 3s, 6s
                        logger.warning(
                            "editorial_llm.chat_text_retrying",
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
                    if attempt < max_retries:
                        wait = 3 * (attempt + 1)
                        logger.warning(
                            "editorial_llm.chat_text_timeout_retrying",
                            attempt=attempt + 1,
                            wait_s=wait,
                        )
                        await asyncio.sleep(wait)
                        continue
                    logger.error(
                        "editorial_llm.chat_text_timeout_exhausted",
                        attempts_exhausted=attempt + 1,
                    )
                    return None
                except Exception as e:
                    logger.error("editorial_llm.chat_text_error", error=str(e))
                    return None

            return None

    async def close(self) -> None:
        """Close the underlying httpx client."""
        if self._client:
            await self._client.aclose()
            self._client = None
