"""Smart source search orchestrator — cascading pipeline."""

import asyncio
import re
import time
from collections.abc import Awaitable, Callable
from datetime import UTC, datetime, timedelta
from urllib.parse import urlparse
from uuid import UUID

import structlog
from sqlalchemy import func, or_, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.database import async_session_maker
from app.models.enums import SourceType
from app.models.host_feed_resolution import HostFeedResolution
from app.models.source import Source
from app.models.source_search_log import SourceSearchLog
from app.models.user import UserInterest
from app.services.rss_parser import RSSParser
from app.services.search.cache import (
    normalize_query,
    search_cache_get,
    search_cache_set,
)
from app.services.search.providers.brave import BraveSearchProvider
from app.services.search.providers.denylist import (
    is_listicle_host,
    is_listicle_title,
)
from app.services.search.providers.google_news import GoogleNewsProvider
from app.services.search.providers.reddit_search import RedditSearchProvider

logger = structlog.get_logger()

# ─── In-memory rate counters (reset on restart) ─────────────────

_brave_calls_month: int = 0
_mistral_calls_month: int = 0
_user_daily_counts: dict[str, int] = {}
_user_daily_reset_date: str = ""

USER_DAILY_LIMIT = 30
# A single curated catalog match is enough to skip the external pipeline:
# the diag (.context/source-search-diag.md) showed that named queries like
# "mediapart" / "monde diplo" land 1 curated hit and produce zero listicles,
# while ≥3 was forcing Brave to fire on obvious lookups.
MIN_RESULTS_FOR_SHORTCIRCUIT = 1
# pg_trgm similarity threshold for fuzzy catalog match.
CATALOG_TRGM_THRESHOLD = 0.30
# Per-URL budget for RSS feed discovery on external candidates. RSSParser
# probes ~14 common suffixes; on slow domains (cnn.com, nbcnews.com…) the
# whole chain can take 40+ s and dominate the user-facing latency. Three
# seconds is enough to resolve well-known publishers and bound worst-case
# latency to ~3-5 s per query.
FEED_DETECT_TIMEOUT_S = 4.0
# host_feed_resolutions TTLs. Positive hits are cheap to refresh and rarely
# move (publishers don't change feed paths often), so 30 days is fine. We
# keep negatives short so a host that gains a feed isn't blacklisted forever.
HOST_FEED_CACHE_TTL_DAYS = 30
HOST_FEED_CACHE_NEGATIVE_TTL_DAYS = 7
# Minimum similarity required for a curated hit to short-circuit the pipeline
# on its own. Below this, we still surface the result but keep calling external
# providers — a weak trigram match isn't strong enough evidence on its own.
CATALOG_SHORTCIRCUIT_TRGM = 0.60


_FRENCH_HINT_TOKENS = {
    "le",
    "la",
    "les",
    "de",
    "du",
    "des",
    "et",
    "actu",
    "actus",
    "actualite",
    "actualites",
    "journal",
    "magazine",
    "presse",
    "info",
    "infos",
    "media",
    "medias",
}


def _looks_french(query: str) -> bool:
    """Cheap heuristic: query contains accented chars or a common FR token."""
    if any(c in query for c in "àâäéèêëîïôöùûüÿç"):
        return True
    tokens = re.split(r"\s+", normalize_query(query))
    return any(t in _FRENCH_HINT_TOKENS for t in tokens if t)


def _is_strong_catalog_match(result: dict, normalized_query: str) -> bool:
    """Return True when a catalog hit clearly matches the query.

    Match conditions: exact name, prefix on a word boundary, or word-boundary
    match inside the name. Substring-only matches (e.g. "le" in "ouest-france")
    do NOT qualify — they would trigger false short-circuits.
    """
    if not normalized_query:
        return False
    name_norm = normalize_query(result.get("name", ""))
    if not name_norm:
        return False
    if name_norm == normalized_query:
        return True
    if name_norm.startswith(normalized_query + " "):
        return True
    return re.search(rf"\b{re.escape(normalized_query)}\b", name_norm) is not None


async def _record_search_log(
    *,
    user_id: str,
    query_raw: str,
    query_normalized: str,
    content_type: str | None,
    expand: bool,
    layers_called: list[str],
    results: list[dict],
    latency_ms: int,
    cache_hit: bool,
) -> None:
    """Persist a row in `source_search_logs`. Best-effort, never raises.

    Uses its own session so the insert survives whatever the caller's
    request-scoped session does (rollback on HTTPException, etc.).
    """
    top = [
        {
            "name": r.get("name"),
            "url": r.get("url"),
            "feed_url": r.get("feed_url"),
            "type": r.get("type"),
            "source_layer": r.get("source_layer"),
            "in_catalog": r.get("in_catalog", False),
            "is_curated": r.get("is_curated", False),
            "score": r.get("score", 0.0),
        }
        for r in results[:5]
    ]
    try:
        async with async_session_maker() as session:
            session.add(
                SourceSearchLog(
                    user_id=UUID(user_id),
                    query_raw=query_raw[:500],
                    query_normalized=query_normalized[:500],
                    content_type=content_type,
                    expand=expand,
                    layers_called=list(layers_called),
                    result_count=len(results),
                    top_results=top,
                    latency_ms=latency_ms,
                    cache_hit=cache_hit,
                )
            )
            await session.commit()
    except Exception as exc:
        logger.warning(
            "source_search_log.persist_failed",
            error=str(exc),
            exc_type=type(exc).__name__,
        )


async def mark_search_abandoned(user_id: str, query: str) -> None:
    """Flag the most recent matching search log as abandoned."""
    normalized = normalize_query(query)
    try:
        async with async_session_maker() as session:
            await session.execute(
                text(
                    """
                    UPDATE source_search_logs
                    SET abandoned = true
                    WHERE id = (
                        SELECT id FROM source_search_logs
                        WHERE user_id = :uid
                          AND query_normalized = :q
                        ORDER BY created_at DESC
                        LIMIT 1
                    )
                    """
                ),
                {"uid": UUID(user_id), "q": normalized},
            )
            await session.commit()
    except Exception as exc:
        logger.warning(
            "source_search_log.mark_abandoned_failed",
            error=str(exc),
            exc_type=type(exc).__name__,
        )


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

    def __init__(
        self,
        db: AsyncSession,
        on_phase1_done: Callable[[], Awaitable[None]] | None = None,
    ) -> None:
        self.db = db
        self._on_phase1_done = on_phase1_done
        self._session_released = False
        self.rss_parser = RSSParser()
        self.brave = BraveSearchProvider()
        self.reddit = RedditSearchProvider()
        self.google_news = GoogleNewsProvider()

    async def _release_session(self) -> None:
        """Release the request-scoped DB session before slow externals.

        Mirrors the digest hot-path pattern (PR #485): the injected session
        is held only for the short phase-1 reads (cache lookup, catalog ILIKE,
        user_themes), then handed back to the pool before LLM/HTTP work so it
        doesn't sit idle for ~30s.
        """
        if self._session_released:
            return
        self._session_released = True
        if self._on_phase1_done is not None:
            try:
                await self._on_phase1_done()
            except Exception as exc:
                logger.warning(
                    "smart_search.release_session_failed",
                    error=str(exc),
                    exc_type=type(exc).__name__,
                )

    async def close(self) -> None:
        await self.rss_parser.close()

    async def search(
        self,
        query: str,
        user_id: str,
        content_type: str | None = None,
        expand: bool = False,
    ) -> dict:
        """Execute the smart search pipeline.

        - ``content_type``: optional filter ("article" / "youtube" / "reddit" /
          "podcast"). When set, the catalog is filtered by ``Source.type`` and
          layers that don't produce that type are skipped (huge latency win
          for type-scoped searches).
        - ``expand``: when True, bypass the catalog short-circuit so the full
          external pipeline runs (used by the "Élargir la recherche" action).

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

        # Cache check (keyed by query + content_type + expand)
        cached = await search_cache_get(self.db, query, content_type, expand)
        if cached:
            await self._release_session()
            elapsed = int((time.monotonic() - start) * 1000)
            cached["cache_hit"] = True
            cached["latency_ms"] = elapsed
            await _record_search_log(
                user_id=user_id,
                query_raw=query,
                query_normalized=normalized,
                content_type=content_type,
                expand=expand,
                layers_called=cached.get("layers_called", []),
                results=cached.get("results", []),
                latency_ms=elapsed,
                cache_hit=True,
            )
            return cached

        query_type = _classify_query(query)
        user_themes = await self._get_user_themes(user_id)

        # (a) Catalog ILIKE (optionally filtered by type)
        catalog_results = await self._search_catalog(
            normalized, user_themes, content_type
        )
        for r in catalog_results:
            if r["url"] not in seen_urls:
                seen_urls.add(r["url"])
                results.append(r)
        layers_called.append("catalog")

        # Aggressive short-circuit: strong name match in catalog.
        # Users can still escape with `expand=True` ("Élargir la recherche").
        if not expand and any(_is_strong_catalog_match(r, normalized) for r in results):
            return await self._finalize(
                normalized,
                results,
                layers_called,
                start,
                False,
                user_id=user_id,
                query_raw=query,
                content_type=content_type,
                expand=expand,
            )

        # Secondary guard: enough curated matches with strong-enough similarity.
        # Weak trigram hits (sim ≥ 0.30) are kept in `results` but must NOT
        # short-circuit on their own — only sim ≥ CATALOG_SHORTCIRCUIT_TRGM does.
        if not expand:
            curated_count = sum(
                1
                for r in results
                if r.get("is_curated")
                and r.get("_similarity", 0.0) >= CATALOG_SHORTCIRCUIT_TRGM
            )
            if curated_count >= MIN_RESULTS_FOR_SHORTCIRCUIT:
                return await self._finalize(
                    normalized,
                    results,
                    layers_called,
                    start,
                    False,
                    user_id=user_id,
                    query_raw=query,
                    content_type=content_type,
                    expand=expand,
                )

        # All phase-1 reads done — release the injected session before any
        # slow external HTTP call (LLM/Brave/GoogleNews). Mirrors PR #485.
        await self._release_session()

        # (b) YouTube API — if signal and type allows
        if content_type in (None, "youtube") and (
            query_type == "youtube_handle" or "youtube" in normalized
        ):
            yt_results = await self._search_youtube(query, user_themes)
            for r in yt_results:
                if r["url"] not in seen_urls:
                    seen_urls.add(r["url"])
                    results.append(r)
            layers_called.append("youtube")

        # (c) Reddit JSON — if signal and type allows
        if content_type in (None, "reddit") and (
            query_type == "reddit_sub" or "reddit" in normalized or "r/" in normalized
        ):
            reddit_results = await self._search_reddit(query, user_themes)
            for r in reddit_results:
                if r["url"] not in seen_urls:
                    seen_urls.add(r["url"])
                    results.append(r)
            layers_called.append("reddit")

        # (d) + (e) Brave Search & Google News — articles/podcasts only.
        # In expand mode we want both layers' results, so we run them in
        # parallel. Otherwise we keep the serial path (Brave first, then
        # short-circuit if it returned anything) — the catalog gate already
        # handled the cheap-hit case, and Brave alone usually fills the
        # 1-result short-circuit, making GNews redundant for non-expand
        # queries.
        settings = get_settings()
        external_eligible = content_type in (None, "article", "podcast")
        brave_eligible = (
            external_eligible
            and self.brave.is_ready
            and _brave_calls_month < settings.brave_monthly_cap
        )

        if expand and external_eligible and brave_eligible:
            brave_results, gnews_results = await asyncio.gather(
                self._search_brave(normalized, user_themes),
                self._search_google_news(normalized, user_themes),
            )
            _brave_calls_month += 1
            for r in brave_results:
                if r["url"] not in seen_urls:
                    seen_urls.add(r["url"])
                    results.append(r)
            layers_called.append("brave")
            for r in gnews_results:
                if r["url"] not in seen_urls:
                    seen_urls.add(r["url"])
                    results.append(r)
            layers_called.append("google_news")

            if _brave_calls_month >= int(settings.brave_monthly_cap * 0.8):
                logger.warning(
                    "smart_search.brave_budget_warning",
                    calls=_brave_calls_month,
                    cap=settings.brave_monthly_cap,
                )
        else:
            if brave_eligible:
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

            if not expand and len(results) >= MIN_RESULTS_FOR_SHORTCIRCUIT:
                return await self._finalize(
                    normalized,
                    results,
                    layers_called,
                    start,
                    False,
                    user_id=user_id,
                    query_raw=query,
                    content_type=content_type,
                    expand=expand,
                )

            if external_eligible:
                gnews_results = await self._search_google_news(normalized, user_themes)
                for r in gnews_results:
                    if r["url"] not in seen_urls:
                        seen_urls.add(r["url"])
                        results.append(r)
                layers_called.append("google_news")

                if not expand and len(results) >= MIN_RESULTS_FOR_SHORTCIRCUIT:
                    return await self._finalize(
                        normalized,
                        results,
                        layers_called,
                        start,
                        False,
                        user_id=user_id,
                        query_raw=query,
                        content_type=content_type,
                        expand=expand,
                    )

        # (f) Mistral fallback — catch-all, skipped when a type filter is set
        if content_type is None and _mistral_calls_month < settings.mistral_monthly_cap:
            mistral_results = await self._search_mistral(normalized, user_themes)
            _mistral_calls_month += 1
            for r in mistral_results:
                if r["url"] not in seen_urls:
                    seen_urls.add(r["url"])
                    results.append(r)
            layers_called.append("mistral")

        return await self._finalize(
            normalized,
            results,
            layers_called,
            start,
            False,
            user_id=user_id,
            query_raw=query,
            content_type=content_type,
            expand=expand,
        )

    # ─── Layer implementations ────────────────────────────────────

    async def _search_catalog(
        self,
        query: str,
        user_themes: list[str],
        content_type: str | None = None,
    ) -> list[dict]:
        """Search catalog: accent-insensitive ILIKE + pg_trgm fuzzy fallback.

        `query` is already normalize_query()-ed (lowercase, accents stripped).
        We compare against `unaccent(lower(name))` so "arret" matches "Arrêt"
        and "le monde diplo" still finds "Le Monde Diplomatique".
        """
        pattern = f"%{query}%"
        unaccent_name = func.unaccent(func.lower(Source.name))
        unaccent_url = func.unaccent(func.lower(Source.url))
        substring_match = or_(unaccent_name.ilike(pattern), unaccent_url.ilike(pattern))
        similarity = func.similarity(unaccent_name, query)
        fuzzy_match = similarity >= CATALOG_TRGM_THRESHOLD

        stmt = (
            select(Source, similarity.label("sim"))
            .where(Source.is_active.is_(True))
            .where(or_(substring_match, fuzzy_match))
            .order_by(
                Source.is_curated.desc(),
                similarity.desc(),
                Source.name,
            )
            .limit(10)
        )
        if content_type:
            stmt = stmt.where(Source.type == SourceType(content_type))
        result = await self.db.execute(stmt)
        rows = result.all()

        items: list[dict] = []
        for source, sim in rows:
            item = self._source_to_result(source, "catalog", user_themes)
            item["_similarity"] = float(sim or 0.0)
            items.append(item)
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

    # Platforms whose host root has no usable feed — the channel/publication
    # lives at the path-level URL (e.g. youtube.com/@channel, x.substack.com/feed).
    # For these we keep the original URL instead of stripping to the host.
    _PATH_LEVEL_PLATFORMS = frozenset(
        {
            "www.youtube.com",
            "youtube.com",
            "m.youtube.com",
            "substack.com",
            "medium.com",
        }
    )

    @staticmethod
    def _root_url(url: str) -> str | None:
        """Return scheme://host for *url*, or None if unparsable."""
        try:
            parsed = urlparse(url)
        except ValueError:
            return None
        if not parsed.scheme or not parsed.netloc:
            return None
        return f"{parsed.scheme}://{parsed.netloc}"

    async def _detect_with_root_fallback(self, url: str) -> tuple[str, dict] | None:
        """Resolve *url* to a feed, preferring the host root.

        External providers (Brave, Google News) overwhelmingly return article
        URLs like ``https://www.lemonde.fr/...article-123.html`` which
        feedparser cannot resolve. The host root (lemonde.fr) is the URL that
        actually exposes the discoverable feed. We probe root only when one
        is parseable; otherwise we fall back to the original URL.

        Falling back from a failed root to the article URL was an explicit
        anti-pattern in the previous design — articles almost never expose
        feeds, the second 5s timeout doubled worst-case latency to ~10s, and
        the probe never showed a case where the article URL recovered a
        feed the root had missed.

        Returns (resolved_url, feed_meta) or None when no feed was found.
        """
        host = (urlparse(url).netloc or "").lower()
        root = self._root_url(url)
        target = root if root and host not in self._PATH_LEVEL_PLATFORMS else url
        feed_meta = await self._cached_detect_feed(target)
        if feed_meta and feed_meta.get("feed_url"):
            return target, feed_meta
        return None

    @staticmethod
    def _cache_key(url: str) -> str | None:
        """Return host[+path] used as cache key. Path-level platforms keyed
        by host+path so that distinct YouTube channels don't collide."""
        try:
            parsed = urlparse(url)
        except ValueError:
            return None
        host = (parsed.netloc or "").lower()
        if not host:
            return None
        if host in SmartSourceSearchService._PATH_LEVEL_PLATFORMS:
            path = parsed.path.rstrip("/").lower()
            return f"{host}{path}" if path else host
        return host

    async def _cached_detect_feed(self, url: str) -> dict | None:
        """Try the host_feed_resolutions cache before doing real detection.

        Stores both positive (feed found) and negative (no feed) results so
        Brave/GNews don't repeat the ~4s detection budget on every request
        for the same publisher. All cache I/O is best-effort: on any error
        we fall through to direct detection.
        """
        key = self._cache_key(url)
        if not key:
            return await self._try_detect_feed(url)

        try:
            async with async_session_maker() as session:
                row = await session.execute(
                    select(HostFeedResolution).where(
                        HostFeedResolution.host == key,
                        HostFeedResolution.expires_at > datetime.now(UTC),
                    )
                )
                cached = row.scalar_one_or_none()
                if cached is not None:
                    if cached.feed_url:
                        return {
                            "feed_url": cached.feed_url,
                            "name": cached.title,
                            "type": cached.type,
                            "favicon_url": cached.logo_url,
                            "description": cached.description,
                            "recent_items": [],
                        }
                    # Negative cache hit — host known to have no feed.
                    return None
        except Exception as exc:
            logger.debug("host_feed_cache.lookup_failed", host=key, error=str(exc))

        feed_meta = await self._try_detect_feed(url)
        await self._cache_feed_meta(key, feed_meta)
        return feed_meta

    async def _cache_feed_meta(self, key: str, feed_meta: dict | None) -> None:
        """Upsert a resolution result into host_feed_resolutions. Best-effort."""
        positive = bool(feed_meta and feed_meta.get("feed_url"))
        ttl_days = (
            HOST_FEED_CACHE_TTL_DAYS if positive else HOST_FEED_CACHE_NEGATIVE_TTL_DAYS
        )
        now = datetime.now(UTC)
        expires = now + timedelta(days=ttl_days)
        try:
            async with async_session_maker() as session:
                await session.execute(
                    text(
                        """
                        INSERT INTO host_feed_resolutions
                            (host, feed_url, type, title, logo_url,
                             description, resolved_at, expires_at)
                        VALUES (:host, :feed_url, :type, :title, :logo_url,
                                :description, :resolved_at, :expires_at)
                        ON CONFLICT (host) DO UPDATE SET
                            feed_url = EXCLUDED.feed_url,
                            type = EXCLUDED.type,
                            title = EXCLUDED.title,
                            logo_url = EXCLUDED.logo_url,
                            description = EXCLUDED.description,
                            resolved_at = EXCLUDED.resolved_at,
                            expires_at = EXCLUDED.expires_at
                        """
                    ),
                    {
                        "host": key,
                        "feed_url": (feed_meta or {}).get("feed_url"),
                        "type": (feed_meta or {}).get("type"),
                        "title": (feed_meta or {}).get("name"),
                        "logo_url": (feed_meta or {}).get("favicon_url"),
                        "description": (feed_meta or {}).get("description"),
                        "resolved_at": now,
                        "expires_at": expires,
                    },
                )
                await session.commit()
        except Exception as exc:
            logger.debug("host_feed_cache.upsert_failed", host=key, error=str(exc))

    async def _try_detect_feed(self, url: str) -> dict | None:
        """Try RSS feed detection on a URL. Returns enrichment dict or None.

        Bounded by ``FEED_DETECT_TIMEOUT_S`` so a slow publisher cannot
        dominate the user-facing latency.
        """
        try:
            detected = await asyncio.wait_for(
                self.rss_parser.detect(url), timeout=FEED_DETECT_TIMEOUT_S
            )
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
        except TimeoutError:
            logger.debug("smart_search.feed_detect_timeout", url=url)
            return None
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

    async def _detect_candidates(
        self,
        candidates: list[tuple[str, str, str]],
        layer: str,
        user_themes: list[str],
    ) -> list[dict]:
        """Run feed detection on candidates in parallel, short-circuit at 3 hits.

        Each candidate is (url, fallback_name, fallback_description). Detection
        runs concurrently; once 3 results carry a feed_url we cancel the
        pending tasks. Avoids waiting on a slow tail when we already have
        enough usable sources to surface.
        """
        if not candidates:
            return []

        async def _resolve(idx: int, url: str):
            detected = await self._detect_with_root_fallback(url)
            return idx, detected

        tasks = [
            asyncio.create_task(_resolve(i, url))
            for i, (url, _, _) in enumerate(candidates)
        ]
        collected: list[tuple[int, tuple[str, dict]]] = []
        loop = asyncio.get_event_loop()
        first_hit_at: float | None = None
        # Once we've collected at least one hit, cap remaining wait to this
        # grace window. Bounds total batch latency when slow candidates
        # never resolve (most common cause of >4s queries).
        GRACE_AFTER_FIRST_HIT_S = 1.5
        try:
            pending = set(tasks)
            while pending:
                if first_hit_at is None:
                    timeout = None
                else:
                    elapsed = loop.time() - first_hit_at
                    timeout = max(0.0, GRACE_AFTER_FIRST_HIT_S - elapsed)
                done, pending = await asyncio.wait(
                    pending,
                    return_when=asyncio.FIRST_COMPLETED,
                    timeout=timeout,
                )
                if not done:
                    break  # grace window elapsed
                for d in done:
                    try:
                        idx, detected = d.result()
                    except Exception:
                        continue
                    if detected is None:
                        continue
                    collected.append((idx, detected))
                    if first_hit_at is None:
                        first_hit_at = loop.time()
                if len(collected) >= 3:
                    break
        finally:
            for t in tasks:
                if not t.done():
                    t.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)

        # Preserve original candidate order (priority from caller).
        collected.sort(key=lambda x: x[0])
        results: list[dict] = []
        for idx, detected in collected:
            _, fallback_name, fallback_desc = candidates[idx]
            resolved_url, feed_meta = detected
            results.append(
                self._build_result(
                    resolved_url,
                    layer,
                    user_themes,
                    feed_meta,
                    fallback_name,
                    fallback_desc,
                )
            )
        return results

    async def _search_brave(self, query: str, user_themes: list[str]) -> list[dict]:
        """Search Brave and keep only candidates that resolve to a real RSS feed.

        Drops listicle hosts, listicle titles, and any URL where neither the
        article URL nor the host root expose a feed — Facteur cannot ingest
        a "source" without a feed.
        """
        brave_results = await self.brave.search(query)
        # First pass: collect non-listicle candidates from the top 8.
        raw_candidates: list[tuple[str, str, str]] = []
        for br in brave_results[:8]:
            url = br.get("url", "")
            title = br.get("title", "")
            if not url:
                continue
            if is_listicle_host(url) or is_listicle_title(title):
                logger.debug("smart_search.brave_listicle_skip", url=url, title=title)
                continue
            raw_candidates.append((url, title, br.get("description", "")))

        if not raw_candidates:
            return []

        # Pre-rank candidates so the top 3 we actually probe are the most
        # likely to carry a feed. Heuristics:
        #   1. Host frequency in the top-8 (repeated host = popular publisher).
        #   2. .fr TLD boost when the query smells French.
        host_counts: dict[str, int] = {}
        for url, _, _ in raw_candidates:
            host = (urlparse(url).netloc or "").lower()
            host_counts[host] = host_counts.get(host, 0) + 1
        prefer_fr = _looks_french(query)

        def _score(item: tuple[str, str, str]) -> tuple[int, int]:
            url, _, _ = item
            host = (urlparse(url).netloc or "").lower()
            fr_bonus = 1 if (prefer_fr and host.endswith(".fr")) else 0
            return (fr_bonus, host_counts.get(host, 0))

        # Stable sort preserves Brave's ranking inside ties. We keep top 5 —
        # parallel detection short-circuits at 3 hits anyway, so extra
        # candidates broaden coverage without extending latency on the
        # happy path; on the unhappy path they cap how often we fall to 0.
        ranked = sorted(raw_candidates, key=_score, reverse=True)
        candidates = ranked[:5]

        return await self._detect_candidates(candidates, "brave", user_themes)

    async def _search_google_news(
        self, query: str, user_themes: list[str]
    ) -> list[dict]:
        """Resolve Google News domains to RSS-bearing sources only."""
        base_urls = await self.google_news.search(query)
        urls = [u for u in base_urls[:8] if u and not is_listicle_host(u)][:5]
        if not urls:
            return []

        return await self._detect_candidates(
            [(u, "", "") for u in urls],
            "google_news",
            user_themes,
        )

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

            urls_and_meta = [
                (u, n, t) for (u, n, t) in urls_and_meta if not is_listicle_host(u)
            ]
            if not urls_and_meta:
                return []

            detections = await asyncio.gather(
                *(self._detect_with_root_fallback(url) for url, _, _ in urls_and_meta)
            )
            results: list[dict] = []
            for (url, name, stype), detected in zip(
                urls_and_meta, detections, strict=True
            ):
                if not detected:
                    continue
                resolved_url, feed_meta = detected
                results.append(
                    self._build_result(
                        resolved_url,
                        "mistral",
                        user_themes,
                        feed_meta,
                        name,
                        fallback_type=stype,
                    )
                )
            return results

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
        *,
        user_id: str,
        query_raw: str,
        content_type: str | None = None,
        expand: bool = False,
    ) -> dict:
        """Sort, trim, cache, log, and return response.

        Hard rule: a result without a `feed_url` is not a usable source and is
        dropped here — the user added this guard explicitly because returning
        article-style results without feeds is the bug we're fixing.
        """
        # Idempotent: ensures phase-1 short-circuit paths also release the
        # injected session before the cache write + log insert.
        await self._release_session()
        results = [r for r in results if r.get("feed_url")]
        # Drop the internal `_similarity` debug field before serializing.
        for r in results:
            r.pop("_similarity", None)

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

        # search_cache_set opens its own short-lived session — never reuses
        # the request-scoped one (which has been released by now).
        await search_cache_set(normalized, response, content_type, expand)

        await _record_search_log(
            user_id=user_id,
            query_raw=query_raw,
            query_normalized=normalized,
            content_type=content_type,
            expand=expand,
            layers_called=layers_called,
            results=results,
            latency_ms=elapsed,
            cache_hit=cache_hit,
        )

        return response
