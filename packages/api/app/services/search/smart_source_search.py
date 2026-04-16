"""Smart source search orchestrator — cascading pipeline."""

import asyncio
import re
import time
from datetime import UTC, datetime
from uuid import UUID

import structlog
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.models.source import Source
from app.models.user import UserInterest
from app.services.rss_parser import RSSParser
from app.services.search.cache import SearchCache, normalize_query
from app.services.search.providers.brave import BraveSearchProvider
from app.services.search.providers.google_news import GoogleNewsProvider
from app.services.search.providers.reddit_search import RedditSearchProvider

logger = structlog.get_logger()

# ─── In-memory rate counters (reset on restart) ─────────────────

_brave_calls_month: int = 0
_mistral_calls_month: int = 0
_user_daily_counts: dict[str, int] = {}
_user_daily_reset_date: str = ""

USER_DAILY_LIMIT = 30
MIN_RESULTS_FOR_SHORTCIRCUIT = 3


def _check_user_rate_limit(user_id: str) -> bool:
    """Returns True if user is within daily limit."""
    global _user_daily_reset_date
    today = datetime.now(UTC).strftime("%Y-%m-%d")
    if _user_daily_reset_date != today:
        _user_daily_counts.clear()
        _user_daily_reset_date = today
    count = _user_daily_counts.get(user_id, 0)
    if count >= USER_DAILY_LIMIT:
        return False
    _user_daily_counts[user_id] = count + 1
    return True


def _classify_query(query: str) -> str:
    """Classify query into: url_like, youtube_handle, reddit_sub, free_text."""
    q = query.strip()
    # URL-like
    if re.match(r"^https?://", q, re.I) or re.match(
        r"^[\w.-]+\.[a-z]{2,6}(/.*)?$", q, re.I
    ):
        return "url_like"
    # YouTube handle
    if re.match(r"^@[\w.-]+$", q):
        return "youtube_handle"
    # Reddit subreddit
    if re.match(r"^r/\w+$", q, re.I):
        return "reddit_sub"
    return "free_text"


def _compute_score(
    layer: str,
    in_catalog: bool,
    is_curated: bool,
    follower_count: int,
    freshness_days: float | None,
    type_match: bool,
    theme_affinity: bool,
) -> float:
    """Compute composite ranking score."""
    layer_scores = {
        "catalog": 1.0,
        "youtube": 0.9,
        "reddit": 0.9,
        "brave": 0.8,
        "google_news": 0.6,
        "mistral": 0.5,
    }
    confidence = layer_scores.get(layer, 0.5)

    # Popularity: normalize follower_count (cap at 100 for max score)
    popularity = min(follower_count / 100.0, 1.0) if in_catalog else 0.0

    # Freshness: 1.0 if < 1 day, 0.0 if > 30 days
    if freshness_days is not None:
        freshness = max(0.0, 1.0 - freshness_days / 30.0)
    else:
        freshness = 0.5

    return (
        0.40 * confidence
        + 0.25 * popularity
        + 0.15 * freshness
        + 0.10 * (1.0 if type_match else 0.0)
        + 0.10 * (1.0 if theme_affinity else 0.0)
    )


class SmartSourceSearchService:
    """Orchestrates the multi-layer smart search pipeline."""

    def __init__(self, db: AsyncSession) -> None:
        self.db = db
        self.cache = SearchCache(db)
        self.rss_parser = RSSParser()
        self.brave = BraveSearchProvider()
        self.reddit = RedditSearchProvider()
        self.google_news = GoogleNewsProvider()

    async def close(self) -> None:
        await self.rss_parser.close()

    async def search(self, query: str, user_id: str) -> dict:
        """Execute the full smart search pipeline.

        Returns a dict matching SmartSearchResponse schema.
        """
        global _brave_calls_month, _mistral_calls_month

        start = time.monotonic()
        normalized = normalize_query(query)
        layers_called: list[str] = []
        results: list[dict] = []
        seen_urls: set[str] = set()

        # Rate limit check
        if not _check_user_rate_limit(user_id):
            return {
                "query_normalized": normalized,
                "results": [],
                "cache_hit": False,
                "layers_called": [],
                "latency_ms": 0,
                "error": "rate_limit_exceeded",
            }

        # Cache check
        cached = await self.cache.get(query)
        if cached:
            elapsed = int((time.monotonic() - start) * 1000)
            cached["cache_hit"] = True
            cached["latency_ms"] = elapsed
            return cached

        query_type = _classify_query(query)
        user_themes = await self._get_user_themes(user_id)

        # (a) Catalog ILIKE
        catalog_results = await self._search_catalog(normalized, user_themes)
        for r in catalog_results:
            if r["url"] not in seen_urls:
                seen_urls.add(r["url"])
                results.append(r)
        layers_called.append("catalog")

        # Short-circuit on curated catalog
        curated_count = sum(1 for r in results if r.get("is_curated"))
        if curated_count >= MIN_RESULTS_FOR_SHORTCIRCUIT:
            return await self._finalize(
                normalized, results, layers_called, start, False
            )

        # (b) YouTube API — if signal
        if query_type == "youtube_handle" or "youtube" in normalized:
            yt_results = await self._search_youtube(query, user_themes)
            for r in yt_results:
                if r["url"] not in seen_urls:
                    seen_urls.add(r["url"])
                    results.append(r)
            layers_called.append("youtube")

        # (c) Reddit JSON — if signal
        if query_type == "reddit_sub" or "reddit" in normalized or "r/" in normalized:
            reddit_results = await self._search_reddit(query, user_themes)
            for r in reddit_results:
                if r["url"] not in seen_urls:
                    seen_urls.add(r["url"])
                    results.append(r)
            layers_called.append("reddit")

        # (d) Brave Search
        settings = get_settings()
        if self.brave.is_ready and _brave_calls_month < settings.brave_monthly_cap:
            brave_results = await self._search_brave(normalized, user_themes)
            _brave_calls_month += 1
            for r in brave_results:
                if r["url"] not in seen_urls:
                    seen_urls.add(r["url"])
                    results.append(r)
            layers_called.append("brave")

            if _brave_calls_month >= int(settings.brave_monthly_cap * 0.8):
                logger.warning(
                    "smart_search.brave_budget_warning",
                    calls=_brave_calls_month,
                    cap=settings.brave_monthly_cap,
                )

        # Short-circuit if enough results
        if len(results) >= MIN_RESULTS_FOR_SHORTCIRCUIT:
            return await self._finalize(
                normalized, results, layers_called, start, False
            )

        # (e) Google News RSS
        gnews_results = await self._search_google_news(normalized, user_themes)
        for r in gnews_results:
            if r["url"] not in seen_urls:
                seen_urls.add(r["url"])
                results.append(r)
        layers_called.append("google_news")

        if len(results) >= MIN_RESULTS_FOR_SHORTCIRCUIT:
            return await self._finalize(
                normalized, results, layers_called, start, False
            )

        # (f) Mistral fallback
        if _mistral_calls_month < settings.mistral_monthly_cap:
            mistral_results = await self._search_mistral(normalized, user_themes)
            _mistral_calls_month += 1
            for r in mistral_results:
                if r["url"] not in seen_urls:
                    seen_urls.add(r["url"])
                    results.append(r)
            layers_called.append("mistral")

        return await self._finalize(normalized, results, layers_called, start, False)

    # ─── Layer implementations ────────────────────────────────────

    async def _search_catalog(self, query: str, user_themes: list[str]) -> list[dict]:
        """Search catalog via ILIKE on name and url."""
        pattern = f"%{query}%"
        stmt = (
            select(Source)
            .where(Source.is_active.is_(True))
            .where((Source.name.ilike(pattern)) | (Source.url.ilike(pattern)))
            .order_by(Source.is_curated.desc())
            .limit(10)
        )
        result = await self.db.execute(stmt)
        sources = result.scalars().all()

        items = []
        for s in sources:
            items.append(self._source_to_result(s, "catalog", user_themes))
        return items

    async def _search_youtube(self, query: str, user_themes: list[str]) -> list[dict]:
        """Resolve YouTube handle to feed via RSSParser."""
        q = query.strip()
        if q.startswith("@"):
            url = f"https://www.youtube.com/{q}"
        else:
            # Try as search term — build a YouTube URL
            url = f"https://www.youtube.com/@{q.replace(' ', '')}"

        try:
            detected = await self.rss_parser.detect(url)
            return [
                {
                    "name": detected.title,
                    "type": "youtube",
                    "url": url,
                    "feed_url": detected.feed_url,
                    "favicon_url": detected.logo_url,
                    "description": detected.description,
                    "in_catalog": False,
                    "is_curated": False,
                    "source_id": None,
                    "recent_items": [
                        {"title": e["title"], "published_at": e.get("published_at", "")}
                        for e in detected.entries[:3]
                    ],
                    "score": _compute_score(
                        "youtube",
                        False,
                        False,
                        0,
                        None,
                        True,
                        any(t in (detected.title or "").lower() for t in user_themes),
                    ),
                    "source_layer": "youtube",
                }
            ]
        except (ValueError, Exception) as e:
            logger.debug("smart_search.youtube_failed", query=query, error=str(e))
            return []

    async def _search_reddit(self, query: str, user_themes: list[str]) -> list[dict]:
        """Search Reddit for subreddits."""
        q = query.strip()
        if q.lower().startswith("r/"):
            q = q[2:]

        results = await self.reddit.search(q)
        items = []
        for r in results:
            items.append(
                {
                    "name": r["name"],
                    "type": "reddit",
                    "url": r["url"],
                    "feed_url": r["feed_url"],
                    "favicon_url": None,
                    "description": r.get("description"),
                    "in_catalog": False,
                    "is_curated": False,
                    "source_id": None,
                    "recent_items": [],
                    "score": _compute_score(
                        "reddit",
                        False,
                        False,
                        min(r.get("subscribers", 0) // 1000, 100),
                        None,
                        True,
                        False,
                    ),
                    "source_layer": "reddit",
                }
            )
        return items

    async def _try_detect_feed(self, url: str) -> dict | None:
        """Try RSS feed detection on a URL. Returns enrichment dict or None."""
        try:
            detected = await self.rss_parser.detect(url)
            return {
                "feed_url": detected.feed_url,
                "name": detected.title,
                "type": detected.feed_type,
                "favicon_url": detected.logo_url,
                "description": detected.description,
                "recent_items": [
                    {
                        "title": e["title"],
                        "published_at": e.get("published_at", ""),
                    }
                    for e in detected.entries[:3]
                ],
            }
        except (ValueError, Exception) as e:
            logger.debug("smart_search.feed_detect_failed", url=url, error=str(e))
            return None

    def _build_result(
        self,
        url: str,
        layer: str,
        user_themes: list[str],
        feed_meta: dict | None,
        fallback_name: str = "",
        fallback_description: str = "",
        fallback_type: str = "article",
    ) -> dict:
        """Build a search result dict, enriched with feed metadata if available."""
        name = (feed_meta or {}).get("name") or fallback_name or url
        return {
            "name": name,
            "type": (feed_meta or {}).get("type") or fallback_type,
            "url": url,
            "feed_url": (feed_meta or {}).get("feed_url"),
            "favicon_url": (feed_meta or {}).get("favicon_url"),
            "description": (feed_meta or {}).get("description") or fallback_description,
            "in_catalog": False,
            "is_curated": False,
            "source_id": None,
            "recent_items": (feed_meta or {}).get("recent_items", []),
            "score": _compute_score(
                layer,
                False,
                False,
                0,
                None,
                False,
                any(t in name.lower() for t in user_themes),
            ),
            "source_layer": layer,
        }

    async def _search_brave(self, query: str, user_themes: list[str]) -> list[dict]:
        """Search Brave, then optionally enrich top URLs via feed discovery."""
        brave_results = await self.brave.search(query)
        urls_and_meta = [
            (br.get("url", ""), br.get("title", ""), br.get("description", ""))
            for br in brave_results[:5]
            if br.get("url")
        ]
        if not urls_and_meta:
            return []

        detections = await asyncio.gather(
            *(self._try_detect_feed(url) for url, _, _ in urls_and_meta)
        )
        return [
            self._build_result(url, "brave", user_themes, det, title, desc)
            for (url, title, desc), det in zip(urls_and_meta, detections, strict=True)
        ]

    async def _search_google_news(
        self, query: str, user_themes: list[str]
    ) -> list[dict]:
        """Search Google News RSS, extract domains, optionally enrich feeds."""
        base_urls = await self.google_news.search(query)
        urls = [u for u in base_urls[:5] if u]
        if not urls:
            return []

        detections = await asyncio.gather(
            *(self._try_detect_feed(url) for url in urls)
        )
        return [
            self._build_result(url, "google_news", user_themes, det)
            for url, det in zip(urls, detections, strict=True)
        ]

    async def _search_mistral(self, query: str, user_themes: list[str]) -> list[dict]:
        """Mistral-small fallback: suggest feed URLs for query."""
        from app.services.editorial.llm_client import EditorialLLMClient

        llm = EditorialLLMClient()
        if not llm.is_ready:
            return []

        try:
            system_prompt = (
                "You are a helpful assistant that suggests RSS feed URLs. "
                "Given a search query about a media source, newsletter, blog, "
                "YouTube channel, or podcast, return a JSON object with a "
                "'suggestions' array. Each suggestion should have 'name', "
                "'url' (the website URL), and 'type' (article/youtube/podcast/reddit). "
                "Return 3-5 suggestions. Only suggest real, well-known sources."
            )
            result = await llm.chat_json(
                system=system_prompt,
                user_message=f"Find RSS feed sources for: {query}",
                model="mistral-small-latest",
                temperature=0.2,
                max_tokens=500,
            )
            await llm.close()

            if not result or not isinstance(result, dict):
                return []

            suggestions = result.get("suggestions", [])
            urls_and_meta = [
                (s.get("url", ""), s.get("name", ""), s.get("type", "article"))
                for s in suggestions[:5]
                if s.get("url")
            ]
            if not urls_and_meta:
                return []

            detections = await asyncio.gather(
                *(self._try_detect_feed(url) for url, _, _ in urls_and_meta)
            )
            return [
                self._build_result(
                    url, "mistral", user_themes, det, name, fallback_type=stype
                )
                for (url, name, stype), det in zip(urls_and_meta, detections, strict=True)
            ]

        except Exception as e:
            logger.warning("smart_search.mistral_failed", error=str(e))
            return []

    # ─── Helpers ──────────────────────────────────────────────────

    def _source_to_result(
        self, source: Source, layer: str, user_themes: list[str]
    ) -> dict:
        """Convert a Source model to a result dict."""
        theme_affinity = source.theme in user_themes if source.theme else False
        return {
            "name": source.name,
            "type": source.type.value if source.type else "article",
            "url": source.url,
            "feed_url": source.feed_url or source.url,
            "favicon_url": source.logo_url,
            "description": source.description,
            "in_catalog": True,
            "is_curated": source.is_curated,
            "source_id": str(source.id),
            "recent_items": [],
            "score": _compute_score(
                layer,
                True,
                source.is_curated,
                0,
                None,
                True,
                theme_affinity,
            ),
            "source_layer": layer,
        }

    async def _get_user_themes(self, user_id: str) -> list[str]:
        """Get list of theme slugs the user follows."""
        try:
            stmt = select(UserInterest.interest_slug).where(
                UserInterest.user_id == UUID(user_id)
            )
            result = await self.db.execute(stmt)
            return [row[0] for row in result.fetchall()]
        except Exception:
            return []

    async def _finalize(
        self,
        normalized: str,
        results: list[dict],
        layers_called: list[str],
        start: float,
        cache_hit: bool,
    ) -> dict:
        """Sort, trim, cache, and return response."""
        # Sort by score descending
        results.sort(key=lambda r: r.get("score", 0), reverse=True)
        results = results[:8]

        elapsed = int((time.monotonic() - start) * 1000)

        response = {
            "query_normalized": normalized,
            "results": results,
            "cache_hit": cache_hit,
            "layers_called": layers_called,
            "latency_ms": elapsed,
        }

        # Cache the result
        try:
            await self.cache.set(normalized, response)
        except Exception as e:
            logger.warning("smart_search.cache_set_failed", error=str(e))

        return response
