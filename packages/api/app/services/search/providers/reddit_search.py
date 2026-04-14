"""Reddit JSON search provider for smart source search."""

import httpx
import structlog

logger = structlog.get_logger()

REDDIT_SEARCH_URL = "https://www.reddit.com/search.json"


class RedditSearchProvider:
    """Client for Reddit public JSON search API."""

    async def search(self, query: str, limit: int = 5) -> list[dict]:
        """Search Reddit for subreddits matching query.

        Returns list of dicts with keys: name, url, feed_url, description, subscribers.
        Returns [] on error (graceful degradation).
        """
        try:
            async with httpx.AsyncClient(
                timeout=2.0,
                headers={
                    "User-Agent": "Facteur/1.0 (RSS reader; +https://facteur.app)",
                },
            ) as client:
                resp = await client.get(
                    REDDIT_SEARCH_URL,
                    params={
                        "q": query,
                        "type": "sr",
                        "limit": str(limit),
                    },
                )
                resp.raise_for_status()
                data = resp.json()

            results = []
            for child in data.get("data", {}).get("children", []):
                sr = child.get("data", {})
                name = sr.get("display_name", "")
                if not name:
                    continue
                results.append({
                    "name": f"r/{name}",
                    "url": f"https://www.reddit.com/r/{name}/",
                    "feed_url": f"https://www.reddit.com/r/{name}/.rss",
                    "description": (sr.get("public_description") or "")[:200],
                    "subscribers": sr.get("subscribers", 0),
                })

            logger.info("reddit.search_success", query=query, count=len(results))
            return results

        except httpx.HTTPStatusError as e:
            logger.warning(
                "reddit.http_error",
                query=query,
                status=e.response.status_code,
            )
            return []
        except Exception as e:
            logger.warning("reddit.search_error", query=query, error=str(e))
            return []
