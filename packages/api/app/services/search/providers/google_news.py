"""Google News RSS provider for smart source search."""

from urllib.parse import quote, urlparse

import feedparser
import httpx
import structlog

logger = structlog.get_logger()

USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) "
    "Chrome/131.0.0.0 Safari/537.36"
)


class GoogleNewsProvider:
    """Extracts base domains from Google News RSS search results."""

    async def search(self, query: str, limit: int = 5) -> list[str]:
        """Search Google News RSS and extract unique base domains.

        Returns list of base URLs (e.g. "https://example.com").
        Returns [] on error (graceful degradation).
        """
        encoded_query = quote(query)
        url = (
            f"https://news.google.com/rss/search"
            f"?q={encoded_query}&hl=fr&gl=FR&ceid=FR:fr"
        )

        try:
            async with httpx.AsyncClient(
                timeout=2.0,
                headers={"User-Agent": USER_AGENT},
                follow_redirects=True,
            ) as client:
                resp = await client.get(url)
                if resp.status_code != 200:
                    logger.warning(
                        "google_news.http_error",
                        query=query,
                        status=resp.status_code,
                    )
                    return []

                feed = feedparser.parse(resp.content)

            seen_domains: set[str] = set()
            base_urls: list[str] = []

            for entry in feed.entries:
                link = entry.get("link", "")
                if not link:
                    continue
                parsed = urlparse(link)
                domain = parsed.netloc.lower()
                # Skip Google's own redirects
                if "google.com" in domain:
                    continue
                if domain not in seen_domains:
                    seen_domains.add(domain)
                    base_urls.append(f"{parsed.scheme}://{domain}")
                    if len(base_urls) >= limit:
                        break

            logger.info(
                "google_news.search_success",
                query=query,
                domains=len(base_urls),
            )
            return base_urls

        except Exception as e:
            logger.warning("google_news.search_error", query=query, error=str(e))
            return []
