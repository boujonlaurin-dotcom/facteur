"""Routers API."""

from app.routers import (
    app_update,
    auth,
    collections,
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
    "app_update",
    "auth",
    "collections",
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
