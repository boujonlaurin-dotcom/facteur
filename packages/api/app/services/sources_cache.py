"""Per-user TTL cache for ``GET /sources`` (the trusted-sources screen).

Cousin of :mod:`app.services.feed_cache` — same single-flight design, lighter
payload (in-memory pydantic model, no serialization).

Background
----------
Sentry shows recurrent pool exhaustion / OperationalError on endpoints that
fan out across multiple sequential queries (PYTHON-4, PYTHON-26).
``GET /sources`` issues 5+ queries on every call (Source, UserSource,
UserPersonalization, UserInterest) and the response is near-identical within
a 30 s window. Caching reduces DB pressure proportionally to repeat hits per
user — exactly the regime that triggers the pool timeouts.

Invalidation
------------
Every mutation that affects the catalog visible to a user MUST call
:py:meth:`SourcesCache.invalidate`. Stale-but-correct is acceptable for
passive reads (≤ 30 s blink); inconsistent-after-write is not.
"""

from __future__ import annotations

import asyncio
import logging
import os
import time
from dataclasses import dataclass
from uuid import UUID

from app.schemas.source import SourceCatalogResponse

logger = logging.getLogger(__name__)


def _ttl_from_env() -> float:
    """Read TTL from env. ``SOURCES_CACHE_TTL_SECONDS=0`` disables the cache."""
    raw = os.environ.get("SOURCES_CACHE_TTL_SECONDS", "30")
    try:
        return max(0.0, float(raw))
    except ValueError:
        logger.warning("sources_cache_invalid_ttl raw=%s, defaulting to 30s", raw)
        return 30.0


@dataclass
class _Entry:
    expires_at: float
    payload: SourceCatalogResponse


class SourcesCache:
    """Per-user TTL cache with single-flight semantics.

    See ``feed_cache.FeedPageCache`` for the rationale on locks and TTL.
    """

    def __init__(self, ttl_seconds: float | None = None) -> None:
        self._ttl = ttl_seconds if ttl_seconds is not None else _ttl_from_env()
        self._entries: dict[UUID, _Entry] = {}
        self._locks: dict[UUID, asyncio.Lock] = {}
        self._hits = 0
        self._misses = 0
        self._invalidations = 0

    @property
    def ttl_seconds(self) -> float:
        return self._ttl

    @property
    def enabled(self) -> bool:
        return self._ttl > 0

    def lock(self, user_id: UUID) -> asyncio.Lock:
        lock = self._locks.get(user_id)
        if lock is None:
            lock = asyncio.Lock()
            self._locks[user_id] = lock
        return lock

    def get(self, user_id: UUID) -> SourceCatalogResponse | None:
        if not self.enabled:
            return None
        entry = self._entries.get(user_id)
        if entry is None or entry.expires_at < time.monotonic():
            self._misses += 1
            return None
        self._hits += 1
        return entry.payload

    def put(self, user_id: UUID, payload: SourceCatalogResponse) -> None:
        if not self.enabled:
            return
        self._entries[user_id] = _Entry(
            expires_at=time.monotonic() + self._ttl,
            payload=payload,
        )

    def invalidate(self, user_id: UUID) -> None:
        if self._entries.pop(user_id, None) is not None:
            self._invalidations += 1

    def stats(self) -> dict[str, int | float]:
        total = self._hits + self._misses
        return {
            "hits": self._hits,
            "misses": self._misses,
            "invalidations": self._invalidations,
            "size": len(self._entries),
            "hit_rate": (self._hits / total) if total else 0.0,
            "ttl_seconds": self._ttl,
        }

    def clear(self) -> None:
        self._entries.clear()
        self._locks.clear()
        self._hits = 0
        self._misses = 0
        self._invalidations = 0


SOURCES_CACHE = SourcesCache()
"""Module-level singleton — import as ``from app.services.sources_cache import SOURCES_CACHE``."""
