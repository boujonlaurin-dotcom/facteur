"""Mistral LLM client for editorial pipeline via httpx.

Uses mistral-large-latest (most capable model) for editorial curation.
Reuses the existing MISTRAL_API_KEY from classification_service.
"""

from __future__ import annotations

import json

import httpx
import structlog

from app.config import get_settings

logger = structlog.get_logger()

MISTRAL_API_URL = "https://api.mistral.ai/v1/chat/completions"


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

    async def chat_json(
        self,
        system: str,
        user_message: str,
        model: str = "mistral-large-latest",
        temperature: float = 0.3,
        max_tokens: int = 1000,
    ) -> dict | list | None:
        """Send a message to Mistral and parse JSON response.

        Returns parsed JSON (dict or list) on success, None on failure.
        """
        if not self._ready:
            logger.warning("editorial_llm.not_ready")
            return None

        client = self._get_client()
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

        try:
            response = await client.post(MISTRAL_API_URL, json=payload)
            response.raise_for_status()

            data = response.json()
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
                prompt_tokens=data.get("usage", {}).get("prompt_tokens"),
                completion_tokens=data.get("usage", {}).get("completion_tokens"),
            )
            return parsed

        except httpx.HTTPStatusError as e:
            logger.error(
                "editorial_llm.http_error",
                status_code=e.response.status_code,
                body=e.response.text[:500],
            )
            return None
        except json.JSONDecodeError as e:
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
    ) -> str | None:
        """Send a message to Mistral and return plain text response.

        Returns raw text string on success, None on failure.
        """
        if not self._ready:
            logger.warning("editorial_llm.not_ready")
            return None

        client = self._get_client()
        payload = {
            "model": model,
            "temperature": temperature,
            "max_tokens": max_tokens,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user_message},
            ],
        }

        try:
            response = await client.post(MISTRAL_API_URL, json=payload)
            response.raise_for_status()

            data = response.json()
            text = data["choices"][0]["message"]["content"].strip()

            logger.info(
                "editorial_llm.chat_text_success",
                model=model,
                prompt_tokens=data.get("usage", {}).get("prompt_tokens"),
                completion_tokens=data.get("usage", {}).get("completion_tokens"),
            )
            return text

        except httpx.HTTPStatusError as e:
            logger.error(
                "editorial_llm.http_error",
                status_code=e.response.status_code,
                body=e.response.text[:500],
            )
            return None
        except Exception as e:
            logger.error("editorial_llm.chat_text_error", error=str(e))
            return None

    async def close(self) -> None:
        """Close the underlying httpx client."""
        if self._client:
            await self._client.aclose()
            self._client = None
