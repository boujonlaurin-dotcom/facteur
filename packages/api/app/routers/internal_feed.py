"""Synthetic feed endpoints (Story 12.2, T1b).

Unauthenticated on purpose: ``SyncService`` fetches these URLs as plain feed
URLs (no admin token), so they must be reachable the same way any external
feed is. Safety is enforced by (1) SSRF-validating the ``host`` param before
any outbound fetch, (2) only ever hitting the fixed ``/wp-json/wp/v2/posts``
path on the target, and (3) a small in-process rate limit to blunt abuse of
this open-ish proxy surface.
"""

import time
from collections import defaultdict
from urllib.parse import urlparse

import structlog
from fastapi import APIRouter, HTTPException, Query, Response, status

from app.services.wordpress_feed import (
    DEFAULT_POSTS,
    MAX_POSTS,
    fetch_wp_posts,
    fetch_wp_site_info,
    render_wp_rss,
)
from app.utils.url_safety import validate_url_for_fetch

logger = structlog.get_logger()

router = APIRouter()

# Coarse per-host rate limit (this endpoint is unauthenticated). A synced
# source hits it every rss_sync_interval, so a generous window is fine.
_RATE_WINDOW_S = 60
_RATE_MAX = 20
_hits: dict[str, list[float]] = defaultdict(list)


def _rate_ok(host: str) -> bool:
    now = time.monotonic()
    cutoff = now - _RATE_WINDOW_S
    _hits[host] = [t for t in _hits[host] if t > cutoff]
    if len(_hits[host]) >= _RATE_MAX:
        return False
    _hits[host].append(now)
    return True


@router.get("/wp")
async def wordpress_synthetic_feed(
    host: str = Query(..., max_length=255),
    limit: int = Query(DEFAULT_POSTS, ge=1, le=MAX_POSTS),
) -> Response:
    """Render a WordPress site's REST posts as an RSS 2.0 feed.

    Used only as a last-resort ``feed_url`` when a site's canonical ``/feed/``
    is absent but the REST API is open (Story 12.2, Palier 1b).
    """
    target = host.strip()
    if not target.startswith(("http://", "https://")):
        target = "https://" + target

    try:
        validate_url_for_fetch(target)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)
        ) from None

    parsed = urlparse(target)
    root = f"{parsed.scheme}://{parsed.netloc}"

    if not _rate_ok(parsed.netloc.lower()):
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many requests for this host",
        )

    posts = await fetch_wp_posts(root, limit)
    if not posts:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="WordPress REST API returned no posts",
        )

    info = await fetch_wp_site_info(root)
    xml = render_wp_rss(
        root,
        posts,
        site_name=(info or {}).get("name"),
        site_description=(info or {}).get("description"),
        limit=limit,
    )
    return Response(
        content=xml,
        media_type="application/rss+xml; charset=utf-8",
        headers={"Cache-Control": "public, max-age=600"},
    )
