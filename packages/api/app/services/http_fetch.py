"""Shared HTTP fetch helpers with an anti-bot (curl-cffi) fallback.

Extracted from ``RSSParser`` so ``SyncService`` can reuse the *exact same*
impersonation logic on the refresh hot-path (Story 12.2, T3) instead of
duplicating it. A feed discovered behind an anti-bot wall at add-time
(``detect()`` already falls back to curl-cffi) otherwise dies at the next
refresh because ``SyncService`` fetched with plain httpx.

Keep this module dependency-light: it must be importable from both the
detection service and the sync worker without pulling feed-parsing code.
"""

from urllib.parse import urljoin

import structlog

from app.utils.url_safety import validate_url_for_fetch

logger = structlog.get_logger()

# Anti-bot markers in response content indicating a CAPTCHA/challenge page.
ANTIBOT_MARKERS = [
    "captcha-delivery.com",
    "datadome",
    "cf-challenge",
    "challenges.cloudflare.com",
    "cf-chl-bypass",
]

# HTTP status codes that carry a redirect Location we should follow.
_REDIRECT_CODES = {301, 302, 303, 307, 308}


def is_antibot_response(status_code: int, content: str) -> bool:
    """Detect if a response looks like an anti-bot challenge.

    A bare 403 is treated as anti-bot (the historical behaviour of
    ``RSSParser._is_antibot_response``); otherwise scan the first 2 KB of the
    body for a known challenge marker.
    """
    if status_code == 403:
        return True
    content_lower = content[:2000].lower()
    return any(marker in content_lower for marker in ANTIBOT_MARKERS)


async def fetch_with_impersonation(url: str, *, timeout: int = 10) -> str | None:
    """Fetch ``url`` using curl-cffi to bypass TLS fingerprinting.

    Returns the response text on a 200, ``None`` on any failure (including
    curl-cffi not being installed). Re-raises ``ValueError`` from SSRF
    validation so callers cannot be tricked into fetching internal addresses.
    Follows up to 6 redirects, re-validating every hop.
    """
    try:
        from curl_cffi.requests import AsyncSession
    except ImportError:
        logger.warning("curl-cffi not installed, skipping anti-bot fallback")
        return None

    try:
        async with AsyncSession(impersonate="chrome", timeout=timeout) as s:
            current_url = validate_url_for_fetch(url)
            for _ in range(6):
                resp = await s.get(
                    current_url,
                    allow_redirects=False,
                    headers={
                        "Accept-Language": "fr-FR,fr;q=0.9,en-US;q=0.8,en;q=0.7",
                        "Accept": "text/html,application/xhtml+xml,application/xml;"
                        "q=0.9,*/*;q=0.8",
                    },
                )
                if resp.status_code in _REDIRECT_CODES:
                    location = resp.headers.get("location")
                    if not location:
                        break
                    current_url = validate_url_for_fetch(urljoin(current_url, location))
                    continue
                if resp.status_code == 200:
                    logger.info("curl-cffi fallback succeeded", url=current_url)
                    return resp.text
                logger.warning(
                    "curl-cffi fallback returned non-200",
                    url=current_url,
                    status=resp.status_code,
                )
                break
    except ValueError:
        raise
    except Exception as e:
        logger.warning("curl-cffi fetch failed", url=url, error=str(e))
    return None
