"""In-memory per-user cache for the default `/api/feed/` page-1 view.

Round 5 fix (`docs/bugs/bug-infinite-load-requests.md`).

Why this exists
---------------
Rounds 1-4 reduced *connections per request* but never addressed the *number
of requests* hitting the recommendation pipeline. Mobile-side stale-while-
revalidate + preload + 403 retries multiply `/api/feed/?page=1` calls per
user session. Each call pays the full price: 500 candidate scoring + 7-12
sequential SELECTs in `_build_carousels` = 1.5-5 s holding 2 DB connections.

Within a 30-second window the output is ~99 % identical (same scoring
inputs, same candidate pool, same user state). Recomputing is wasted work.

Design
------
- **Per-user**, in-memory dict, keyed by `user_id`.
- TTL configurable via `FEED_CACHE_TTL_SECONDS` env var (default 30 s,
  set to `0` to disable the cache entirely without redeploy — kill switch).
- **Single-flight via per-user `asyncio.Lock`** to prevent thundering herd
  on cache miss (concurrent first requests for the same user serialise on
  the lock; the 2nd+ pick up the cached value populated by the 1st).
- **Eviction by writes** — every endpoint that mutates user state
  (`save`, `like`, `hide`, `mute`, `impress`, `refresh`) MUST call
  `FEED_CACHE.invalidate(user_id)`. Stale-but-correct is acceptable for
  passive reads (30 s blink); inconsistent-after-write is not.
- **Cache key scope** = the *default* mobile view only:
  `offset == 0` + `limit == 20` + no filter (mode/theme/topic/source/entity
  /keyword) + `serein == False` + `saved_only == False`. Filtered/paginated
  views bypass the cache entirely (lower volume, harder to invalidate
  correctly, lower ROI).
- **Hit telemetry** — hit/miss counters logged every 60 s on stderr so
  we can validate the hit rate without external infra.

Memory budget
-------------
~150 KB per cached payload × 100 DAU ceiling ≈ 15 MB worst case. Safe on
a 1 GB Railway pod.
"""

from __future__ import annotations

import asyncio
import logging
import os
import time
from dataclasses import dataclass
from uuid import UUID

logger = logging.getLogger(__name__)


def _ttl_from_env() -> float:
    """Read TTL from env. Returns `0.0` (cache disabled) on parse failure
    or explicit `FEED_CACHE_TTL_SECONDS=0`."""
    raw = os.environ.get("FEED_CACHE_TTL_SECONDS", "30")
    try:
        return max(0.0, float(raw))
    except ValueError:
        logger.warning("feed_cache_invalid_ttl raw=%s, defaulting to 30s", raw)
        return 30.0


@dataclass
class _Entry:
    expires_at: float
    payload: bytes


class FeedPageCache:
    """Per-user TTL cache with single-flight semantics.

    Thread-safety note: every method assumes it runs on the same asyncio
    event loop. The `_locks` dict is mutated only inside `_lock()` which is
    called from coroutines — no cross-thread access.
    """

    def __init__(self, ttl_seconds: float | None = None) -> None:
        self._ttl = ttl_seconds if ttl_seconds is not None else _ttl_from_env()
        self._entries: dict[UUID, _Entry] = {}
        self._locks: dict[UUID, asyncio.Lock] = {}
        self._hits = 0
        self._misses = 0
        self._invalidations = 0
        self._last_flush_at = time.monotonic()

    @property
    def ttl_seconds(self) -> float:
        return self._ttl

    @property
    def enabled(self) -> bool:
        return self._ttl > 0

    def lock(self, user_id: UUID) -> asyncio.Lock:
        """Return (or lazily create) the asyncio.Lock for `user_id`.

        Public so callers can do the canonical pattern:
            async with FEED_CACHE.lock(user_id):
                hit = FEED_CACHE.get(user_id)
                if hit: return hit
                payload = compute(...)
                FEED_CACHE.put(user_id, payload)
                return payload
        """
        lock = self._locks.get(user_id)
        if lock is None:
            lock = asyncio.Lock()
            self._locks[user_id] = lock
        return lock

    def get(self, user_id: UUID) -> bytes | None:
        """Return cached payload if fresh, else `None`. Updates hit/miss counters."""
        if not self.enabled:
            return None
        entry = self._entries.get(user_id)
        now = time.monotonic()
        if entry is None or entry.expires_at < now:
            self._misses += 1
            self._maybe_flush_telemetry(now)
            return None
        self._hits += 1
        self._maybe_flush_telemetry(now)
        return entry.payload

    def put(self, user_id: UUID, payload: bytes) -> None:
        """Store `payload` for `user_id` with TTL."""
        if not self.enabled:
            return
        self._entries[user_id] = _Entry(
            expires_at=time.monotonic() + self._ttl,
            payload=payload,
        )

    def invalidate(self, user_id: UUID) -> None:
        """Drop `user_id` cache entry (called by every write endpoint)."""
        if self._entries.pop(user_id, None) is not None:
            self._invalidations += 1

    def stats(self) -> dict[str, int | float]:
        """Snapshot for tests / health endpoint."""
        total = self._hits + self._misses
        return {
            "hits": self._hits,
            "misses": self._misses,
            "invalidations": self._invalidations,
            "size": len(self._entries),
            "hit_rate": (self._hits / total) if total else 0.0,
            "ttl_seconds": self._ttl,
        }

    def reset_stats(self) -> None:
        """Test helper."""
        self._hits = 0
        self._misses = 0
        self._invalidations = 0
        self._last_flush_at = time.monotonic()

    def clear(self) -> None:
        """Test helper."""
        self._entries.clear()
        self._locks.clear()

    def _maybe_flush_telemetry(self, now: float) -> None:
        if now - self._last_flush_at < 60.0:
            return
        s = self.stats()
        logger.info(
            "feed_cache_stats hits=%d misses=%d invalidations=%d "
            "size=%d hit_rate=%.2f ttl=%.0fs",
            s["hits"],
            s["misses"],
            s["invalidations"],
            s["size"],
            s["hit_rate"],
            s["ttl_seconds"],
        )
        self._last_flush_at = now


FEED_CACHE = FeedPageCache()
"""Module-level singleton — import as `from app.services.feed_cache import FEED_CACHE`."""
