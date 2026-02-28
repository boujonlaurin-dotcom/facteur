import asyncio
import re
from urllib.parse import urljoin

import feedparser
import httpx
import structlog
from bs4 import BeautifulSoup
from pydantic import BaseModel

from app.config import get_settings

logger = structlog.get_logger()


class DetectedFeed(BaseModel):
    feed_url: str
    title: str = "Unknown Feed"
    description: str | None = None
    feed_type: str = "rss"  # rss, atom, youtube, podcast, reddit
    logo_url: str | None = None
    entries: list[dict] = []


class RSSParser:
    """Service to parse and detect RSS feeds."""

    def __init__(self):
        self.client = httpx.AsyncClient(
            timeout=7.0,
            follow_redirects=True,
            headers={
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
                "Accept-Language": "en-US,en;q=0.9",
            },
            cookies={"CONSENT": "YES+cb.20210328-17-p0.en+FX+430"},
        )

    async def close(self):
        await self.client.aclose()

    async def parse(self, url: str) -> dict:
        """
        Parses a direct RSS/Atom feed URL using feedparser.
        Returns the raw dict from feedparser.
        This is a low-level method.
        """
        loop = asyncio.get_event_loop()

        try:
            response = await self.client.get(url)
            response.raise_for_status()
            content = response.text
        except Exception as e:
            raise ValueError(f"Failed to fetch RSS URI: {str(e)}")

        feed = await loop.run_in_executor(None, feedparser.parse, content)

        if feed.bozo:
            logger.warning(
                "Feedparser reported bozo", url=url, error=feed.bozo_exception
            )

        return feed

    # ─── YouTube Channel ID Resolution ────────────────────────────

    async def _resolve_youtube_channel_id(self, url: str) -> str | None:
        """Resolve a YouTube URL to a channel_id using the Data API v3."""
        # 1. Extract identifier from URL
        # Direct channel ID: /channel/UCxxxxxx
        match = re.search(r"/channel/(UC[\w-]+)", url)
        if match:
            return match.group(1)

        # Handle: /@handle or /c/name
        handle = None
        handle_match = re.search(r"/@([\w.-]+)", url)
        if handle_match:
            handle = handle_match.group(1)

        custom_match = re.search(r"/c/([\w.-]+)", url)
        custom_name = custom_match.group(1) if custom_match else None

        # Video URL: extract channel_id from page HTML (still works for watch pages)
        video_match = re.search(r"/watch\?v=([\w-]+)", url)
        if video_match:
            return await self._channel_id_from_video_page(url)

        # 2. Try YouTube Data API v3
        api_key = get_settings().youtube_api_key
        if api_key and (handle or custom_name):
            channel_id = await self._youtube_api_resolve(
                api_key, handle=handle, custom_name=custom_name
            )
            if channel_id:
                return channel_id

        # 3. Fallback: scrape channelId from page HTML (works sometimes)
        return await self._channel_id_from_html(url)

    async def _youtube_api_resolve(
        self, api_key: str, handle: str | None = None, custom_name: str | None = None
    ) -> str | None:
        """Call YouTube Data API v3 to resolve a handle or custom name to channel_id."""
        try:
            if handle:
                # forHandle works for @handle URLs
                resp = await self.client.get(
                    "https://www.googleapis.com/youtube/v3/channels",
                    params={"forHandle": handle, "part": "id", "key": api_key},
                )
                resp.raise_for_status()
                data = resp.json()
                items = data.get("items", [])
                if items:
                    channel_id = items[0]["id"]
                    logger.info(
                        "YouTube API resolved handle",
                        handle=handle,
                        channel_id=channel_id,
                    )
                    return channel_id

            if custom_name:
                # Search for custom URL name
                resp = await self.client.get(
                    "https://www.googleapis.com/youtube/v3/search",
                    params={
                        "q": custom_name,
                        "type": "channel",
                        "part": "id",
                        "maxResults": "1",
                        "key": api_key,
                    },
                )
                resp.raise_for_status()
                data = resp.json()
                items = data.get("items", [])
                if items:
                    channel_id = items[0]["id"]["channelId"]
                    logger.info(
                        "YouTube API resolved custom name",
                        name=custom_name,
                        channel_id=channel_id,
                    )
                    return channel_id

        except Exception as e:
            logger.warning("YouTube API call failed", error=str(e))

        return None

    async def _channel_id_from_video_page(self, url: str) -> str | None:
        """Extract channel_id from a YouTube video watch page HTML."""
        try:
            resp = await self.client.get(url)
            if resp.status_code == 200:
                match = re.search(r'"channelId":"(UC[\w-]+)"', resp.text)
                if match:
                    logger.info(
                        "Extracted channel_id from video page",
                        channel_id=match.group(1),
                    )
                    return match.group(1)
        except Exception as e:
            logger.warning("Video page channel_id extraction failed", error=str(e))
        return None

    async def _channel_id_from_html(self, url: str) -> str | None:
        """Fallback: try to extract channelId from page HTML via regex."""
        try:
            resp = await self.client.get(url)
            if resp.status_code == 200:
                match = re.search(r'"channelId":"(UC[\w-]+)"', resp.text)
                if match:
                    logger.info(
                        "Extracted channel_id from HTML fallback",
                        channel_id=match.group(1),
                    )
                    return match.group(1)
        except Exception as e:
            logger.warning("HTML channel_id fallback failed", error=str(e))
        return None

    # ─── Main Detection ───────────────────────────────────────────

    async def detect(self, url: str) -> DetectedFeed:
        """
        Smart detection of a feed from a URL.
        1. Platform-specific handlers (YouTube, Reddit).
        2. Tries to parse directly as RSS.
        3. HTML auto-discovery via <link rel="alternate">.
        4. Common suffix fallback.
        """
        logger.info("Detecting feed", url=url)
        loop = asyncio.get_event_loop()

        # ── SPECIAL: Reddit URL detection ─────────────────────────
        reddit_match = re.match(
            r"https?://(?:www\.|old\.)?reddit\.com/r/([\w]+)/?", url
        )
        logger.info("Reddit pattern check", url=url, matched=bool(reddit_match))
        if reddit_match:
            subreddit = reddit_match.group(1)
            rss_url = f"https://www.reddit.com/r/{subreddit}/.rss"
            logger.info("Reddit URL detected", subreddit=subreddit, rss_url=rss_url)
            try:
                feed_resp = await self.client.get(rss_url)
                feed_resp.raise_for_status()
                reddit_feed = await loop.run_in_executor(
                    None, feedparser.parse, feed_resp.text
                )
                if len(reddit_feed.entries) > 0:
                    return await self._format_response(rss_url, reddit_feed)
                logger.warning("Reddit RSS feed empty", subreddit=subreddit)
            except httpx.HTTPStatusError as e:
                logger.warning(
                    "Reddit RSS fetch HTTP error",
                    subreddit=subreddit,
                    status=e.response.status_code,
                    error=str(e),
                )
            except Exception as e:
                logger.warning(
                    "Reddit RSS fetch failed", subreddit=subreddit, error=str(e)
                )
            raise ValueError(
                f"Could not fetch RSS feed for r/{subreddit}. The subreddit may not exist."
            )

        # ── SPECIAL: YouTube feed URL (already resolved) ─────────
        if "youtube.com/feeds/videos.xml" in url:
            logger.info("YouTube feed URL detected, parsing directly", url=url)
            try:
                feed_resp = await self.client.get(url)
                feed_resp.raise_for_status()
                yt_feed = await loop.run_in_executor(
                    None, feedparser.parse, feed_resp.text
                )
                if len(yt_feed.entries) > 0:
                    return await self._format_response(url, yt_feed)
            except Exception as e:
                logger.warning(
                    "Failed to parse YouTube feed URL",
                    url=url,
                    error=str(e),
                )
            raise ValueError("YouTube feed is empty or invalid.")

        # ── SPECIAL: YouTube URL detection ────────────────────────
        if "youtube.com" in url or "youtu.be" in url:
            logger.info("YouTube URL detected, resolving channel_id", url=url)
            channel_id = await self._resolve_youtube_channel_id(url)

            if channel_id:
                rss_url = (
                    f"https://www.youtube.com/feeds/videos.xml?channel_id={channel_id}"
                )
                logger.info(
                    "Resolved YouTube channel",
                    channel_id=channel_id,
                    rss_url=rss_url,
                )
                try:
                    feed_resp = await self.client.get(rss_url)
                    feed_resp.raise_for_status()
                    yt_feed = await loop.run_in_executor(
                        None, feedparser.parse, feed_resp.text
                    )
                    if len(yt_feed.entries) > 0:
                        return await self._format_response(rss_url, yt_feed)
                except Exception as e:
                    logger.warning(
                        "Failed to parse YouTube feed",
                        rss_url=rss_url,
                        error=str(e),
                    )

            logger.warning("Failed to resolve YouTube channel_id", url=url)
            raise ValueError("Could not resolve YouTube channel. Please check the URL.")

        # ── Stage 1: Direct RSS parse ─────────────────────────────
        try:
            response = await self.client.get(url)
            logger.info("Fetched URL", url=url, status_code=response.status_code)
            response.raise_for_status()
            content = response.text
        except Exception as e:
            raise ValueError(f"Could not access URL: {str(e)}")

        feed_data = await loop.run_in_executor(None, feedparser.parse, content)

        if not feed_data.bozo and len(feed_data.entries) > 0:
            return await self._format_response(url, feed_data)

        if len(feed_data.entries) > 0 and "title" in feed_data.feed:
            return await self._format_response(url, feed_data)

        # ── Stage 2: HTML Auto-Discovery ──────────────────────────
        soup = BeautifulSoup(content, "html.parser")
        rss_links = soup.find_all("link", rel="alternate")

        found_url = None
        for link in rss_links:
            type_attr = link.get("type", "").lower()
            href = link.get("href")

            if "oembed" in type_attr:
                continue
            if "comments" in type_attr or "comments" in (href or "").lower():
                continue

            if "rss" in type_attr or "atom" in type_attr or "xml" in type_attr:
                if href:
                    found_url = urljoin(url, href) if href.startswith("/") else href
                    break

        if found_url:
            logger.info("Found RSS link in HTML", page_url=url, rss_url=found_url)
            if found_url != url:
                try:
                    feed_resp = await self.client.get(found_url)
                    feed_resp.raise_for_status()
                    found_feed_data = await loop.run_in_executor(
                        None, feedparser.parse, feed_resp.text
                    )
                    if len(found_feed_data.entries) > 0:
                        return await self._format_response(found_url, found_feed_data)
                except Exception as e:
                    logger.warning(
                        "Failed to parse discovered feed",
                        rss_url=found_url,
                        error=str(e),
                    )

        # ── Stage 3: Common Suffix Fallback ───────────────────────
        if not found_url:
            common_suffixes = ["/feed", "/rss", "/rss.xml", "/feed.xml"]
            for suffix in common_suffixes:
                try_url = url.rstrip("/") + suffix
                logger.info("Trying common RSS suffix", try_url=try_url)
                try:
                    resp = await self.client.get(try_url)
                    if resp.status_code == 200:
                        suffix_feed = await loop.run_in_executor(
                            None, feedparser.parse, resp.text
                        )
                        if not suffix_feed.bozo and len(suffix_feed.entries) > 0:
                            logger.info("Found valid feed via suffix", url=try_url)
                            return await self._format_response(try_url, suffix_feed)
                except Exception:
                    continue

        raise ValueError("No RSS feed found on this page.")

    # ─── Response Formatting ──────────────────────────────────────

    async def _format_response(self, url: str, feed_data) -> DetectedFeed:
        feed = feed_data.feed

        # Detect type
        feed_type = "rss"
        if "atom" in feed_data.version:
            feed_type = "atom"

        # SPECIAL: YouTube feed
        if "youtube.com/feeds/videos.xml" in url:
            feed_type = "youtube"

        # SPECIAL: Reddit feed
        if "reddit.com/r/" in url and ".rss" in url:
            feed_type = "reddit"

        # Image
        logo = None
        if "image" in feed and "href" in feed.image:
            logo = feed.image.href

        entries = []
        for e in feed_data.entries[:3]:
            entries.append(
                {
                    "title": e.get("title", "No Title"),
                    "link": e.get("link", ""),
                    "published_at": e.get("published", ""),
                }
            )

        return DetectedFeed(
            feed_url=url,
            title=feed.get("title", "Unknown Feed"),
            description=feed.get("description", "")[:200]
            if "description" in feed
            else None,
            feed_type=feed_type,
            logo_url=logo,
            entries=entries,
        )
