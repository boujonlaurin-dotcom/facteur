"""Service de détection d'articles payants (paywall).

Détection multi-signaux:
1. JSON-LD Schema.org `isAccessibleForFree` (signal prioritaire, standard Google)
2. Meta tag `og:article:content_tier` (Courrier International, etc.)
3. Scoring RSS fallback: keywords, URL patterns, contenu court

Le signal HTML (1+2) est fiable car déclaratif (le média lui-même déclare l'article payant).
Le scoring (3) sert de filet de sécurité quand pas de HTML disponible.
"""

import json
import re
import time

import structlog

logger = structlog.get_logger()

# Default paywall config used as fallback for sources without custom config
DEFAULT_PAYWALL_CONFIG: dict = {
    "keywords": [
        "Réservé aux abonnés",
        "Article réservé aux abonnés",
        "Article réservé",
        "Contenu réservé",
        "Contenu payant",
        "Abonnez-vous",
        "Article premium",
        "Pour lire la suite",
        "S'abonner",
        "🔒",
        "🔐",
    ],
    "url_patterns": [
        "/premium/",
        "/abonnes/",
        "/subscribers/",
    ],
    "min_content_length": 200,
}

PAYWALL_THRESHOLD = 5

# In-memory cache: source_id -> (config, expiry_timestamp)
_config_cache: dict[str, tuple[dict, float]] = {}
_CACHE_TTL_SECONDS = 3600  # 1 hour


def _get_config(source_id: str, paywall_config: dict | None) -> dict:
    """Get paywall config for a source, with in-memory caching."""
    now = time.monotonic()
    cache_key = str(source_id)

    cached = _config_cache.get(cache_key)
    if cached and cached[1] > now:
        return cached[0]

    if paywall_config and any(
        [
            paywall_config.get("keywords"),
            paywall_config.get("url_patterns"),
            paywall_config.get("min_content_length"),
        ]
    ):
        config = paywall_config
    else:
        config = DEFAULT_PAYWALL_CONFIG

    _config_cache[cache_key] = (config, now + _CACHE_TTL_SECONDS)
    return config


def detect_paywall_from_html(html_head: str) -> bool | None:
    """Detect paywall from article HTML head using structured data.

    Checks (in order):
    1. JSON-LD Schema.org `isAccessibleForFree` field
    2. Meta tag `og:article:content_tier` (value "locked" = paid)

    Args:
        html_head: First ~50KB of the article HTML (enough for <head> + JSON-LD)

    Returns:
        True (paid), False (free), or None (no signal found)
    """
    # 1. Parse JSON-LD blocks for isAccessibleForFree
    json_ld_pattern = re.compile(
        r'<script[^>]+type=["\']application/ld\+json["\'][^>]*>(.*?)</script>',
        re.DOTALL | re.IGNORECASE,
    )
    for match in json_ld_pattern.finditer(html_head):
        try:
            data = json.loads(match.group(1))
            # Handle both single object and array of objects
            items = data if isinstance(data, list) else [data]
            for item in items:
                if not isinstance(item, dict):
                    continue
                access = item.get("isAccessibleForFree")
                if access is not None:
                    # Handle bool, string "False"/"True", and "false"/"true"
                    if isinstance(access, bool):
                        return not access  # isAccessibleForFree=false → is_paid=True
                    if isinstance(access, str):
                        return access.lower() in ("false", "0", "no")
        except (json.JSONDecodeError, TypeError, AttributeError):
            continue

    # 2. Check og:article:content_tier meta tag
    tier_pattern = re.compile(
        r'<meta\s+property=["\']og:article:content_tier["\']\s+content=["\'](\w+)["\']',
        re.IGNORECASE,
    )
    tier_match = tier_pattern.search(html_head)
    if tier_match:
        tier_value = tier_match.group(1).lower()
        if tier_value in ("locked", "metered"):
            return True
        if tier_value == "free":
            return False

    # 3. Check JS variable patterns (e.g., Le Figaro: window.FFF.isPremium = true)
    premium_js_pattern = re.compile(
        r"isPremium\s*[=:]\s*(true|false)",
        re.IGNORECASE,
    )
    premium_match = premium_js_pattern.search(html_head)
    if premium_match:
        return premium_match.group(1).lower() == "true"

    return None


def detect_paywall(
    title: str,
    description: str | None,
    url: str,
    html_content: str | None,
    source_id: str,
    paywall_config: dict | None = None,
    html_head: str | None = None,
) -> bool:
    """Detect if an article is behind a paywall.

    Uses HTML structured data as primary signal (reliable, declarative).
    Falls back to keyword/URL scoring when no HTML is available.

    Args:
        title: Article title
        description: Article description/summary
        url: Article URL
        html_content: Article HTML content (may be truncated in RSS)
        source_id: Source UUID as string (for caching)
        paywall_config: Source-specific paywall config (JSONB from DB)
        html_head: First ~50KB of the article page HTML (for JSON-LD detection)

    Returns:
        True if article is likely behind a paywall
    """
    # Priority 1: HTML-based detection (JSON-LD, meta tags)
    if html_head:
        html_result = detect_paywall_from_html(html_head)
        if html_result is not None:
            if html_result:
                logger.debug(
                    "paywall_detected_html",
                    title=title[:80],
                    source_id=source_id,
                )
            return html_result

    # Priority 2: Scoring fallback (RSS keywords, URL patterns, content length)
    config = _get_config(source_id, paywall_config)
    score = 0

    # 2a. Keyword detection in title + description + content (+3 per match, max once)
    keywords = config.get("keywords", [])
    if keywords:
        searchable_text = (title or "").lower()
        if description:
            searchable_text += " " + description.lower()
        if html_content:
            searchable_text += " " + html_content.lower()

        for keyword in keywords:
            if keyword.lower() in searchable_text:
                score += 3
                break  # Only count keyword match once

    # 2b. URL pattern detection (+3 per match, max once)
    url_patterns = config.get("url_patterns", [])
    if url_patterns and url:
        url_lower = url.lower()
        for pattern in url_patterns:
            if pattern.lower() in url_lower:
                score += 3
                break  # Only count URL pattern once

    # 2c. Content length check (+2 if content is suspiciously short)
    min_content_length = config.get("min_content_length")
    if min_content_length is not None:
        content_text = html_content or description or ""
        # Strip HTML tags for length check
        plain_text = re.sub(r"<[^>]+>", "", content_text).strip()
        if len(plain_text) < min_content_length:
            score += 2

    is_paid = score >= PAYWALL_THRESHOLD
    if is_paid:
        logger.debug(
            "paywall_detected_scoring",
            title=title[:80],
            score=score,
            source_id=source_id,
        )

    return is_paid


def clear_cache() -> None:
    """Clear the in-memory config cache (useful for testing)."""
    _config_cache.clear()
