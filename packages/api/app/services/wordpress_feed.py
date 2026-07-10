"""WordPress REST → synthetic RSS (Story 12.2, T1b).

Some WordPress sites keep the REST API open (``/wp-json/wp/v2/posts``) while
their canonical ``/feed/`` is disabled or broken. Rather than add a
``fetch_method`` column + an alternate parser in ``SyncService`` (a migration
on the shared prod DB), we expose the REST payload as a *synthetic* RSS feed
served by our own backend. ``detect()`` stores that internal URL as the
``feed_url`` and ``SyncService`` fetches it like any other feed, unchanged.

This module is the single source of truth for both:
  * ``detect()`` Stage 4c (to confirm posts exist + build the DetectedFeed), and
  * the ``/internal/feed/wp`` endpoint (to render the RSS on demand).

SSRF: every outbound fetch is validated with ``validate_url_for_fetch`` and
falls back to curl-cffi only on an anti-bot response.
"""

from __future__ import annotations

import html
import json
import os
import re
from datetime import UTC, datetime
from email.utils import format_datetime
from urllib.parse import urlparse
from xml.sax.saxutils import escape

import certifi
import httpx
import structlog

from app.config import get_settings
from app.services.http_fetch import fetch_with_impersonation, is_antibot_response
from app.utils.url_safety import validate_url_for_fetch

logger = structlog.get_logger()


def internal_feed_base_url() -> str | None:
    """Absolute base URL of *this* backend, used to build synthetic feed URLs.

    ``detect()`` stores ``{base}/internal/feed/wp?host=…`` as a source's
    ``feed_url``; that only works if we know our own public origin. Prefer the
    explicit ``internal_feed_base_url`` setting, else fall back to Railway's
    auto-injected ``RAILWAY_PUBLIC_DOMAIN``. Returns ``None`` when neither is
    configured (local/dev), which disables the WP-REST synthetic rung instead
    of persisting a broken URL.
    """
    base = (get_settings().internal_feed_base_url or "").strip()
    if not base:
        domain = os.environ.get("RAILWAY_PUBLIC_DOMAIN", "").strip()
        if domain:
            base = f"https://{domain}"
    base = base.rstrip("/")
    return base or None


# Cap what a caller can ask the synthetic feed to render. WP REST caps at 100
# per page; 20 is plenty for a digest and keeps the endpoint cheap.
DEFAULT_POSTS = 20
MAX_POSTS = 50

_TAG_RE = re.compile(r"<[^>]+>")


def _strip_tags(value: str) -> str:
    """Best-effort strip of HTML tags from a rendered WP title/excerpt."""
    return html.unescape(_TAG_RE.sub("", value or "")).strip()


def wp_rest_posts_url(root: str, limit: int) -> str:
    """Return the WP REST posts URL for a validated site root."""
    per_page = max(1, min(limit, MAX_POSTS))
    return (
        f"{root.rstrip('/')}/wp-json/wp/v2/posts"
        f"?per_page={per_page}&orderby=date&order=desc"
    )


async def _safe_get_json(url: str) -> object | None:
    """GET a JSON document with SSRF validation + curl-cffi anti-bot fallback.

    Returns the parsed JSON (list/dict) or ``None`` on any failure.
    """
    validated = validate_url_for_fetch(url)
    try:
        async with httpx.AsyncClient(
            timeout=8.0,
            follow_redirects=True,
            verify=certifi.where(),
            headers={
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                "Accept": "application/json",
            },
        ) as client:
            resp = await client.get(validated)
            if resp.status_code == 200:
                try:
                    return resp.json()
                except (json.JSONDecodeError, ValueError):
                    return None
            if is_antibot_response(resp.status_code, resp.text):
                impersonated = await fetch_with_impersonation(validated)
                if impersonated:
                    try:
                        return json.loads(impersonated)
                    except (json.JSONDecodeError, ValueError):
                        return None
    except ValueError:
        raise
    except Exception as exc:  # network/timeout — degrade gracefully
        logger.debug("wp_rest.fetch_failed", url=url, error=str(exc))
    return None


async def fetch_wp_posts(root: str, limit: int = DEFAULT_POSTS) -> list[dict] | None:
    """Fetch recent posts from a site's WordPress REST API.

    ``root`` must already be an ``scheme://host`` string. Returns a non-empty
    list of post dicts, or ``None`` when the endpoint is absent/empty/not WP.
    """
    data = await _safe_get_json(wp_rest_posts_url(root, limit))
    if not isinstance(data, list) or not data:
        return None
    # Guard against a REST endpoint that returns something list-shaped but not
    # posts (e.g. an error array). A real post carries a rendered title.
    posts = [p for p in data if isinstance(p, dict) and "title" in p and "link" in p]
    return posts or None


async def fetch_wp_site_info(root: str) -> dict | None:
    """Best-effort site name/description from ``/wp-json/`` (WP core route)."""
    data = await _safe_get_json(f"{root.rstrip('/')}/wp-json/")
    if isinstance(data, dict) and (data.get("name") or data.get("description")):
        return {
            "name": _strip_tags(data.get("name", "")) or None,
            "description": _strip_tags(data.get("description", "")) or None,
        }
    return None


def _post_pubdate(post: dict) -> str:
    """RFC-822 pubDate from a WP post, falling back to now()."""
    raw = post.get("date_gmt") or post.get("date") or ""
    try:
        dt = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=UTC)
    except (ValueError, AttributeError):
        dt = datetime.now(UTC)
    return format_datetime(dt)


def post_entries(posts: list[dict], limit: int = DEFAULT_POSTS) -> list[dict]:
    """Compact ``{title, link, published_at}`` entries for DetectedFeed preview."""
    entries: list[dict] = []
    for post in posts[:limit]:
        title = (
            _strip_tags((post.get("title") or {}).get("rendered", "")) or "Sans titre"
        )
        entries.append(
            {
                "title": title,
                "link": post.get("link", ""),
                "published_at": _post_pubdate(post),
            }
        )
    return entries


def render_wp_rss(
    root: str,
    posts: list[dict],
    *,
    site_name: str | None = None,
    site_description: str | None = None,
    limit: int = DEFAULT_POSTS,
) -> str:
    """Render WP REST posts as a feedparser-parseable RSS 2.0 document."""
    channel_title = escape(site_name or urlparse(root).netloc or "WordPress")
    channel_desc = escape(site_description or "Flux généré depuis l'API WordPress")
    items: list[str] = []
    for post in posts[:limit]:
        title = (
            _strip_tags((post.get("title") or {}).get("rendered", "")) or "Sans titre"
        )
        link = post.get("link", "")
        guid = (post.get("guid") or {}).get("rendered") or link
        excerpt = (post.get("excerpt") or {}).get("rendered", "")
        content = (post.get("content") or {}).get("rendered", "") or excerpt
        pubdate = _post_pubdate(post)
        items.append(
            "    <item>\n"
            f"      <title>{escape(title)}</title>\n"
            f"      <link>{escape(link)}</link>\n"
            f'      <guid isPermaLink="false">{escape(guid)}</guid>\n'
            f"      <pubDate>{escape(pubdate)}</pubDate>\n"
            f"      <description><![CDATA[{excerpt}]]></description>\n"
            f"      <content:encoded><![CDATA[{content}]]></content:encoded>\n"
            "    </item>"
        )
    items_xml = "\n".join(items)
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<rss version="2.0" '
        'xmlns:content="http://purl.org/rss/1.0/modules/content/">\n'
        "  <channel>\n"
        f"    <title>{channel_title}</title>\n"
        f"    <link>{escape(root)}</link>\n"
        f"    <description>{channel_desc}</description>\n"
        f"{items_xml}\n"
        "  </channel>\n"
        "</rss>\n"
    )
