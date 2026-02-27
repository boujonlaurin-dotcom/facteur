"""Routers API."""

from app.routers import (
    auth,
    contents,
    digest,
    feed,
    internal,
    personalization,
    progress,
    sources,
    streaks,
    subscription,
    users,
    webhooks,
)

__all__ = [
    "auth",
    "contents",
    "digest",
    "feed",
    "sources",
    "streaks",
    "subscription",
    "users",
    "webhooks",
    "internal",
    "progress",
    "personalization",
]
