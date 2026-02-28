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

# Anti-bot markers in response content indicating CAPTCHA/challenge pages
_ANTIBOT_MARKERS = [
    "captcha-delivery.com",
    "datadome",
    "cf-challenge",
    "challenges.cloudflare.com",
    "cf-chl-bypass",
]

# Regex to detect feed-like paths in <a href> attributes
_FEED_HREF_PATTERN = re.compile(
    r"/(feed|rss|atom)(\.xml|\.rss)?(/[\w-]*)?$",
    re.IGNORECASE,
)

# Keywords in link text that suggest an RSS link
_FEED_TEXT_KEYWORDS = ["rss", "flux rss", "syndication", "feed", "fil rss"]


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

    # ─── Helpers ──────────────────────────────────────────────────

    @staticmethod
    def _is_feed_content_type(response: httpx.Response) -> bool:
        """Check if HTTP response Content-Type suggests RSS/Atom feed."""
        ct = response.headers.get("content-type", "").lower()
        html_indicators = ["text/html", "application/xhtml"]
        if any(h in ct for h in html_indicators):
            return False
        feed_indicators = ["xml", "rss", "atom"]
        if any(f in ct for f in feed_indicators):
            return True
        # Unknown content type (e.g. text/plain) — let feedparser try
        return True

    @staticmethod
    def _is_antibot_response(status_code: int, content: str) -> bool:
        """Detect if a response is an anti-bot challenge."""
        if status_code == 403:
            return True
        content_lower = content[:2000].lower()
        return any(marker in content_lower for marker in _ANTIBOT_MARKERS)

    async def _fetch_with_impersonation(self, url: str) -> str | None:
        """Fallback fetch using curl-cffi to bypass TLS fingerprinting."""
        try:
            from curl_cffi.requests import AsyncSession
        except ImportError:
            logger.warning("curl-cffi not installed, skipping anti-bot fallback")
            return None

        try:
            async with AsyncSession(impersonate="chrome", timeout=10) as s:
                resp = await s.get(
                    url,
                    headers={
                        "Accept-Language": "fr-FR,fr;q=0.9,en-US;q=0.8,en;q=0.7",
                        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                    },
                )
                if resp.status_code == 200:
                    logger.info("curl-cffi fallback succeeded", url=url)
                    return resp.text
                logger.warning(
                    "curl-cffi fallback returned non-200",
                    url=url,
                    status=resp.status_code,
                )
        except Exception as e:
            logger.warning("curl-cffi fetch failed", url=url, error=str(e))
        return None

    @staticmethod
    def _try_platform_transform(url: str) -> str | None:
        """Transform known platform URLs to their RSS feed URLs.

        Returns the feed URL if a platform match is found, None otherwise.
        No HTTP requests — purely URL pattern matching.
        Note: Reddit and YouTube are handled separately in detect().
        """
        # Skip platforms with dedicated handlers in detect()
        if "youtube.com" in url or "youtu.be" in url or "reddit.com" in url:
            return None

        # Substack: anything.substack.com → /feed
        if re.match(r"https?://[\w-]+\.substack\.com", url):
            return url.rstrip("/") + "/feed"

        # GitHub Releases: github.com/owner/repo → /releases.atom
        gh_match = re.match(
            r"https?://github\.com/([\w.-]+)/([\w.-]+)/?$", url
        )
        if gh_match:
            return f"https://github.com/{gh_match.group(1)}/{gh_match.group(2)}/releases.atom"

        # GitHub Commits: github.com/owner/repo/commits → /commits.atom
        gh_commits = re.match(
            r"https?://github\.com/([\w.-]+)/([\w.-]+)/commits", url
        )
        if gh_commits:
            return f"https://github.com/{gh_commits.group(1)}/{gh_commits.group(2)}/commits.atom"

        # Mastodon: instance/@user → .rss
        if re.match(r"https?://[\w.-]+/@\w+/?$", url):
            return url.rstrip("/") + ".rss"

        # Medium: medium.com/publication → /feed/publication
        medium_match = re.match(r"https?://medium\.com/([\w-]+)/?$", url)
        if medium_match:
            return f"https://medium.com/feed/{medium_match.group(1)}"

        return None

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

        Pipeline:
        0. Platform-specific URL transforms (Substack, GitHub, Mastodon, Medium).
        1. Platform-specific handlers (Reddit, YouTube).
        2. Fetch URL (httpx → curl-cffi fallback on 403/CAPTCHA).
        3. Direct feedparser parse.
        4. HTML <link rel="alternate"> auto-discovery.
        4b. HTML <a href> deep scan for feed-like links.
        5. Expanded suffix fallback with Content-Type validation.
        """
        logger.info("Detecting feed", url=url)
        loop = asyncio.get_event_loop()
        detection_log: list[str] = []

        # ── Step 0: Platform-specific URL transforms ──────────────
        transformed_url = self._try_platform_transform(url)
        if transformed_url:
            logger.info(
                "Platform transform matched",
                original=url,
                feed_url=transformed_url,
            )
            detection_log.append(f"platform_transform={transformed_url}")
            try:
                resp = await self.client.get(transformed_url)
                if resp.status_code == 200:
                    feed_data = await loop.run_in_executor(
                        None, feedparser.parse, resp.text
                    )
                    if len(feed_data.entries) > 0:
                        return await self._format_response(transformed_url, feed_data)
                detection_log.append("platform_transform_feed=no_entries")
            except Exception as e:
                detection_log.append(f"platform_transform_error={e}")
                logger.warning(
                    "Platform transform feed failed, continuing detection",
                    error=str(e),
                )

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

        # ── Stage 1: Fetch URL (httpx → curl-cffi fallback) ────────
        content = None
        try:
            response = await self.client.get(url)
            logger.info("Fetched URL", url=url, status_code=response.status_code)

            if self._is_antibot_response(response.status_code, response.text):
                logger.info("Anti-bot detected, trying curl-cffi fallback", url=url)
                detection_log.append(f"httpx={response.status_code}/antibot")
                impersonated = await self._fetch_with_impersonation(url)
                if impersonated:
                    content = impersonated
                    detection_log.append("curl_cffi=success")
                else:
                    detection_log.append("curl_cffi=failed")
                    raise ValueError(
                        f"Site blocked automated access (HTTP {response.status_code}). "
                        "Try pasting the RSS feed URL directly if you know it."
                    )
            else:
                response.raise_for_status()
                content = response.text
                detection_log.append(f"httpx={response.status_code}")
        except ValueError:
            raise
        except Exception as e:
            logger.info("httpx fetch failed, trying curl-cffi", url=url, error=str(e))
            detection_log.append(f"httpx_error={e}")
            impersonated = await self._fetch_with_impersonation(url)
            if impersonated:
                content = impersonated
                detection_log.append("curl_cffi=success")
            else:
                detection_log.append("curl_cffi=failed")
                raise ValueError(f"Could not access URL: {str(e)}")

        # ── Stage 2: Direct feedparser parse ──────────────────────
        feed_data = await loop.run_in_executor(None, feedparser.parse, content)

        if not feed_data.bozo and len(feed_data.entries) > 0:
            detection_log.append("direct_parse=success")
            return await self._format_response(url, feed_data)

        if len(feed_data.entries) > 0 and "title" in feed_data.feed:
            detection_log.append("direct_parse=success_with_title")
            return await self._format_response(url, feed_data)

        detection_log.append(
            f"direct_parse=fail(bozo={feed_data.bozo},entries={len(feed_data.entries)})"
        )

        # ── Stage 3: HTML <link rel="alternate"> auto-discovery ───
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
                    if href.startswith("/") or not href.startswith("http"):
                        found_url = urljoin(url, href)
                    else:
                        found_url = href
                    break

        if found_url:
            logger.info("Found RSS link in HTML", page_url=url, rss_url=found_url)
            detection_log.append(f"link_alternate={found_url}")
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
        else:
            detection_log.append("link_alternate=none")

        # ── Stage 3b: HTML <a href> deep scan for feed links ──────
        candidate_urls: list[str] = []
        seen: set[str] = set()

        for a_tag in soup.find_all("a", href=True):
            href = a_tag.get("href", "")

            matched = _FEED_HREF_PATTERN.search(href)
            if not matched:
                link_text = (a_tag.get_text() + " " + a_tag.get("title", "")).lower()
                if not any(kw in link_text for kw in _FEED_TEXT_KEYWORDS):
                    continue

            if href.startswith("/"):
                href = urljoin(url, href)
            elif not href.startswith("http"):
                continue

            if href not in seen and href != url:
                seen.add(href)
                candidate_urls.append(href)

        if candidate_urls:
            detection_log.append(f"a_tag_scan={len(candidate_urls)}_candidates")
            for candidate in candidate_urls[:5]:
                try:
                    cand_resp = await self.client.get(candidate)
                    if (
                        cand_resp.status_code == 200
                        and self._is_feed_content_type(cand_resp)
                    ):
                        cand_feed = await loop.run_in_executor(
                            None, feedparser.parse, cand_resp.text
                        )
                        if len(cand_feed.entries) > 0:
                            logger.info("Found feed via <a> tag scan", url=candidate)
                            return await self._format_response(candidate, cand_feed)
                except Exception:
                    continue
        else:
            detection_log.append("a_tag_scan=0_candidates")

        # ── Stage 4: Expanded suffix fallback + Content-Type check
        common_suffixes = [
            "/feed",       # WordPress
            "/rss",        # Generic
            "/feed.xml",   # Hugo, Jekyll, Eleventy
            "/rss.xml",    # Drupal, custom
            "/atom.xml",   # Atom (Jekyll, Ghost)
            "/index.xml",  # Hugo default
            "/feed/all",   # Custom CMS (e.g. grimper.com)
            "/feed/rss",   # CMS variants
            "/blog/feed",  # WordPress with /blog prefix
            "/.rss",       # Reddit-style
        ]
        suffix_tried = 0
        for suffix in common_suffixes:
            try_url = url.rstrip("/") + suffix
            logger.info("Trying common RSS suffix", try_url=try_url)
            try:
                resp = await self.client.get(try_url)
                suffix_tried += 1
                if resp.status_code == 403:
                    continue
                if resp.status_code == 200 and self._is_feed_content_type(resp):
                    suffix_feed = await loop.run_in_executor(
                        None, feedparser.parse, resp.text
                    )
                    if not suffix_feed.bozo and len(suffix_feed.entries) > 0:
                        logger.info("Found valid feed via suffix", url=try_url)
                        return await self._format_response(try_url, suffix_feed)
            except Exception:
                continue

        detection_log.append(
            f"suffix_fallback=tried_{suffix_tried}_of_{len(common_suffixes)}"
        )

        # ── Failure: detailed diagnostic ──────────────────────────
        log_str = "; ".join(detection_log)
        raise ValueError(f"No RSS feed found. Tried: {log_str}")

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
