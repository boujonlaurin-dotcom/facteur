"""Denylist + listicle detection helpers for external search providers.

External search providers (Brave, Google News) frequently surface SEO
"listicle" articles ("Top 60 Best RSS Feeds…") rather than actual sources.
We filter those out before returning anything to the client.
"""

import re
from urllib.parse import urlparse

# Hosts that mostly publish "Best of X RSS feeds" listicles or generic
# aggregator content — never useful as a Facteur source on their own.
LISTICLE_HOSTS: frozenset[str] = frozenset(
    {
        "feedspot.com",
        "blog.feedspot.com",
        "rss.feedspot.com",
        "floridapolitics.com",
        "votersselfdefense.org",
        "vote-smart.org",
        "smartvoter.org",
        "rsslookup.com",
        "rssfeedwidget.com",
        "rss.com",
        "anyleads.com",
        "detailed.com",
        # Wikipedia exposes a feed but it's not a media source.
        "wikipedia.org",
        "fr.wikipedia.org",
        "en.wikipedia.org",
    }
)

# Generic aggregator/portal paths we don't want surfaced. Match against the
# full URL host+path lower-cased.
LISTICLE_PATH_PATTERNS: tuple[re.Pattern[str], ...] = (
    re.compile(r"medium\.com/tag/"),
    re.compile(r"medium\.com/topic/"),
    re.compile(r"reddit\.com/r/[^/]+/(?:top|new|comments)/"),
)

# Title regexes that scream "listicle". Case-insensitive.
LISTICLE_TITLE_PATTERNS: tuple[re.Pattern[str], ...] = (
    re.compile(r"^\s*(?:the\s+)?(?:top|best)\s+\d+\b", re.I),
    re.compile(r"^\s*\d+\s+(?:best|top|great|popular)\b", re.I),
    re.compile(r"\brss feeds?\s*$", re.I),
    re.compile(r"\b(?:list|guide|directory)\s+of\s+(?:rss|feeds|blogs|news)\b", re.I),
)


def is_listicle_host(url: str) -> bool:
    """Return True when *url* belongs to a known listicle / aggregator host."""
    try:
        host = (urlparse(url).hostname or "").lower()
    except ValueError:
        return False
    if not host:
        return False
    if host.startswith("www."):
        host = host[4:]
    if host in LISTICLE_HOSTS:
        return True
    full = url.lower()
    return any(p.search(full) for p in LISTICLE_PATH_PATTERNS)


def is_listicle_title(title: str | None) -> bool:
    """Return True when *title* matches a listicle pattern."""
    if not title:
        return False
    return any(p.search(title) for p in LISTICLE_TITLE_PATTERNS)
