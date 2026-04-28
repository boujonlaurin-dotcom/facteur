"""Brave Search API provider for smart source search."""

import httpx
import structlog

from app.config import get_settings

logger = structlog.get_logger()

BRAVE_SEARCH_URL = "https://api.search.brave.com/res/v1/web/search"


class BraveSearchProvider:
    """Client for Brave Search API (free tier: 2000 req/month)."""

    def __init__(self) -> None:
        settings = get_settings()
        self._api_key = settings.brave_api_key
        self._ready = bool(self._api_key)

    @property
    def is_ready(self) -> bool:
        return self._ready

    async def search(self, query: str, count: int = 5) -> list[dict]:
        """Search Brave for web results related to query.

        Returns list of dicts with keys: url, title, description.
        Returns [] on error (graceful degradation).
        """
        if not self._ready:
            logger.warning("brave.not_ready", message="BRAVE_API_KEY not set")
            return []

        try:
            async with httpx.AsyncClient(timeout=2.0) as client:
                resp = await client.get(
                    BRAVE_SEARCH_URL,
                    params={
                        # Send the bare query — appending "RSS feed site blog"
                        # systematically pulled in SEO listicles ("Top 60 best
                        # political RSS feeds…") instead of real sources.
                        "q": query,
                        "count": str(count),
                        "safesearch": "moderate",
                        "result_filter": "web",
                        # Bias the index toward French content. Without this,
                        # "politis" ranks Politis Cyprus above Politis.fr.
                        "country": "fr",
                        "search_lang": "fr",
                        "ui_lang": "fr-FR",
                    },
                    headers={
                        "Accept": "application/json",
                        "Accept-Encoding": "gzip",
                        "X-Subscription-Token": self._api_key,
                    },
                )
                resp.raise_for_status()
                data = resp.json()

            results = []
            for item in data.get("web", {}).get("results", []):
                results.append(
                    {
                        "url": item.get("url", ""),
                        "title": item.get("title", ""),
                        "description": item.get("description", ""),
                    }
                )

            logger.info("brave.search_success", query=query, count=len(results))
            return results

        except httpx.HTTPStatusError as e:
            logger.warning(
                "brave.http_error",
                query=query,
                status=e.response.status_code,
            )
            return []
        except Exception as e:
            logger.warning("brave.search_error", query=query, error=str(e))
            return []
