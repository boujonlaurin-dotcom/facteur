"""Thin Anthropic Messages API client via httpx.

Pattern follows classification_service.py (Mistral via httpx).
"""

from __future__ import annotations

import json

import httpx
import structlog

from app.config import get_settings

logger = structlog.get_logger()

ANTHROPIC_API_URL = "https://api.anthropic.com/v1/messages"
ANTHROPIC_VERSION = "2023-06-01"


class AnthropicClient:
    """Async client for Anthropic Claude API."""

    def __init__(self) -> None:
        settings = get_settings()
        self._api_key = settings.anthropic_api_key
        self._ready = bool(self._api_key)
        self._client: httpx.AsyncClient | None = None

        if not self._ready:
            logger.warning(
                "anthropic_client.no_api_key",
                message="ANTHROPIC_API_KEY not set. Editorial pipeline unavailable.",
            )

    @property
    def is_ready(self) -> bool:
        return self._ready

    def _get_client(self) -> httpx.AsyncClient:
        if self._client is None:
            self._client = httpx.AsyncClient(
                timeout=30.0,
                headers={
                    "x-api-key": self._api_key,
                    "anthropic-version": ANTHROPIC_VERSION,
                    "content-type": "application/json",
                },
            )
        return self._client

    async def chat_json(
        self,
        system: str,
        user_message: str,
        model: str = "claude-sonnet-4-6",
        temperature: float = 0.3,
        max_tokens: int = 1000,
    ) -> dict | list | None:
        """Send a message to Claude and parse JSON response.

        Returns parsed JSON (dict or list) on success, None on failure.
        """
        if not self._ready:
            logger.warning("anthropic_client.not_ready")
            return None

        client = self._get_client()
        payload = {
            "model": model,
            "max_tokens": max_tokens,
            "temperature": temperature,
            "system": system,
            "messages": [{"role": "user", "content": user_message}],
        }

        try:
            response = await client.post(ANTHROPIC_API_URL, json=payload)
            response.raise_for_status()

            data = response.json()
            text = data["content"][0]["text"]

            # Strip markdown code fences if present
            text = text.strip()
            if text.startswith("```"):
                # Remove first line (```json or ```) and last line (```)
                lines = text.split("\n")
                text = "\n".join(lines[1:-1] if lines[-1].strip() == "```" else lines[1:])
                text = text.strip()

            parsed = json.loads(text)

            logger.info(
                "anthropic_client.success",
                model=model,
                input_tokens=data.get("usage", {}).get("input_tokens"),
                output_tokens=data.get("usage", {}).get("output_tokens"),
            )
            return parsed

        except httpx.HTTPStatusError as e:
            logger.error(
                "anthropic_client.http_error",
                status_code=e.response.status_code,
                body=e.response.text[:500],
            )
            return None
        except json.JSONDecodeError as e:
            logger.error(
                "anthropic_client.json_parse_error",
                error=str(e),
                raw_text=text[:500] if "text" in dir() else "no_text",
            )
            return None
        except Exception as e:
            logger.error("anthropic_client.unexpected_error", error=str(e))
            return None

    async def close(self) -> None:
        """Close the underlying httpx client."""
        if self._client:
            await self._client.aclose()
            self._client = None
