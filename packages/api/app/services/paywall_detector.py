"""Service de détection d'articles payants (paywall).

Algorithme de scoring par source avec cache in-memory.
- Keywords dans titre/description/contenu: +3 points
- URL patterns: +3 points
- Contenu trop court (min_content_length): +2 points
- Seuil: score >= 5 → is_paid = True
"""

import re
import time
from typing import Optional

import structlog

logger = structlog.get_logger()

# Default paywall config used as fallback for sources without custom config
DEFAULT_PAYWALL_CONFIG: dict = {
    "keywords": [
        "Réservé aux abonnés",
        "Article réservé aux abonnés",
        "Contenu réservé",
        "Abonnez-vous",
        "Article premium",
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


def _get_config(source_id: str, paywall_config: Optional[dict]) -> dict:
    """Get paywall config for a source, with in-memory caching."""
    now = time.monotonic()
    cache_key = str(source_id)

    cached = _config_cache.get(cache_key)
    if cached and cached[1] > now:
        return cached[0]

    if paywall_config and any([
        paywall_config.get("keywords"),
        paywall_config.get("url_patterns"),
        paywall_config.get("min_content_length"),
    ]):
        config = paywall_config
    else:
        config = DEFAULT_PAYWALL_CONFIG

    _config_cache[cache_key] = (config, now + _CACHE_TTL_SECONDS)
    return config


def detect_paywall(
    title: str,
    description: Optional[str],
    url: str,
    html_content: Optional[str],
    source_id: str,
    paywall_config: Optional[dict] = None,
) -> bool:
    """Detect if an article is behind a paywall using scoring algorithm.

    Args:
        title: Article title
        description: Article description/summary
        url: Article URL
        html_content: Article HTML content (may be truncated in RSS)
        source_id: Source UUID as string (for caching)
        paywall_config: Source-specific paywall config (JSONB from DB)

    Returns:
        True if article is likely behind a paywall (score >= threshold)
    """
    config = _get_config(source_id, paywall_config)
    score = 0

    # 1. Keyword detection in title + description + content (+3 per match, max once)
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

    # 2. URL pattern detection (+3 per match, max once)
    url_patterns = config.get("url_patterns", [])
    if url_patterns and url:
        url_lower = url.lower()
        for pattern in url_patterns:
            if pattern.lower() in url_lower:
                score += 3
                break  # Only count URL pattern once

    # 3. Content length check (+2 if content is suspiciously short)
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
            "paywall_detected",
            title=title[:80],
            score=score,
            source_id=source_id,
        )

    return is_paid


def clear_cache() -> None:
    """Clear the in-memory config cache (useful for testing)."""
    _config_cache.clear()
