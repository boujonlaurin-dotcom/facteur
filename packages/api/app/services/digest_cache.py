"""Short-lived cache for immutable digest render inputs.

The digest and essentiel endpoints are commonly called together on mobile.
Both render the same ``daily_digest`` JSON and fetch the same content/source
rows before overlaying per-user action state. This cache keeps only the
content/source snapshots; read/save/like/dismiss and completion state still
come from fresh queries on every request.
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass
from datetime import date, datetime
from uuid import UUID

from cachetools import TTLCache

from app.models.enums import ContentType
from app.schemas.content import SourceMini


@dataclass(frozen=True)
class CachedDigestContent:
    id: UUID
    title: str
    url: str
    thumbnail_url: str | None
    description: str | None
    html_content: str | None
    topics: list[str]
    entities: list[str]
    content_type: ContentType
    duration_seconds: int | None
    published_at: datetime
    is_paid: bool
    source_id: UUID
    source: SourceMini


DigestContentCacheKey = tuple[UUID, date, bool, UUID]


class DigestContentCache:
    """TTL cache with per-key single-flight locks."""

    def __init__(self, ttl_seconds: int = 60, maxsize: int = 512) -> None:
        self._entries: TTLCache[DigestContentCacheKey, dict[UUID, CachedDigestContent]]
        self._entries = TTLCache(maxsize=maxsize, ttl=ttl_seconds)
        self._locks: dict[DigestContentCacheKey, asyncio.Lock] = {}

    def get(self, key: DigestContentCacheKey) -> dict[UUID, CachedDigestContent] | None:
        return self._entries.get(key)

    def put(
        self,
        key: DigestContentCacheKey,
        value: dict[UUID, CachedDigestContent],
    ) -> None:
        self._entries[key] = value
        stale = [k for k in self._locks if k not in self._entries]
        for k in stale:
            del self._locks[k]

    def lock(self, key: DigestContentCacheKey) -> asyncio.Lock:
        lock = self._locks.get(key)
        if lock is None:
            lock = asyncio.Lock()
            self._locks[key] = lock
        return lock


DIGEST_CONTENT_CACHE = DigestContentCache()
