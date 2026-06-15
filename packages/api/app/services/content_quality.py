"""Quality helpers for content supplied directly by RSS feeds."""

import re

CONTENT_QUALITY_FULL = 500
CONTENT_QUALITY_PARTIAL = 100


def strip_html(html_text: str) -> str:
    """Strip HTML tags and collapse whitespace."""
    text = re.sub(r"<[^>]+>", " ", html_text)
    return re.sub(r"\s+", " ", text).strip()


def compute_content_quality(content: str | None) -> str:
    """Classify HTML or plain text as full, partial, or insufficient."""
    if not content:
        return "none"
    length = len(strip_html(content))
    if length >= CONTENT_QUALITY_FULL:
        return "full"
    if length >= CONTENT_QUALITY_PARTIAL:
        return "partial"
    return "none"
