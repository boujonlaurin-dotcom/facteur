"""In-memory per-user cache for `/api/feed/` page-1 views.

Round 5 fix (`docs/bugs/bug-infinite-load-requests.md`).
Extended (app-load slowdown investigation) to cache the **personalized
Tournée sections** — the ~10 parallel `personalized=true` calls fired at
cold-open, the single hottest transaction (p95 ~10 s).

Why this exists
---------------
Rounds 1-4 reduced *connections per request* but never addressed the *number
of requests* hitting the recommendation pipeline. Mobile-side stale-while-
revalidate + preload + 403 retries multiply `/api/feed/?page=1` calls per
user session. Each call pays the full price: 500 candidate scoring + 7-12
sequential SELECTs in `_build_carousels` = 1.5-5 s holding 2 DB connections.

The same recompute-every-time problem hits the personalized Tournée sections
even harder: a cold-open fans out ~10 `personalized=true` calls (one per
theme/topic/source section), none of which were cache-eligible — every open,
pull-to-refresh, or re-fetch paid the full pillars scoring pipeline again.

Within a short window the output is ~99 % identical (same scoring inputs,
same candidate pool, same user state). Recomputing is wasted work.

Design
------
- **Per-user, per-variant**, in-memory dict, keyed by `(user_id, variant)`.
  `variant is None` = the default page-1 view (unchanged behavior). A
  non-None `variant` string identifies a personalized section view (derived
  from theme/topic/source_id/serein/limit by the caller).
- TTL configurable via env (default view: `FEED_CACHE_TTL_SECONDS`, default
  30 s; personalized: `FEED_CACHE_PERSONALIZED_TTL_SECONDS`, default 60 s).
  Either set to `0` to disable that class of caching without redeploy —
  independent kill switches.
- **Single-flight via per-key `asyncio.Lock`** to prevent thundering herd
  on cache miss (concurrent first requests for the same key serialise on the
  lock; the 2nd+ pick up the cached value populated by the 1st).
- **Eviction by writes** — every endpoint that mutates user state
  (`save`, `like`, `hide`, `mute`, `impress`, `refresh`) MUST call
  `FEED_CACHE.invalidate(user_id)`, which purges **all** variants for that
  user (default + every personalized section). Stale-but-correct is
  acceptable for passive reads (blink); inconsistent-after-write is not.
- **Default-view key scope** = the *default* mobile view only:
  `offset == 0` + `limit == 20` + no filter (mode/theme/topic/source/entity
  /keyword) + `serein == False` + `saved_only == False` + not personalized.
- **Hit telemetry** — hit/miss counters logged every 60 s on stderr so
  we can validate the hit rate without external infra.

Memory budget
-------------
Default payload ~150 KB; personalized section payloads ~50 KB × ~10 sections.
~50-65 MB worst case at 100 DAU ceiling. Safe on a 1 GB Railway pod.
"""

from __future__ import annotations

import asyncio
import logging
import os
import time
from dataclasses import dataclass
from uuid import UUID

logger = logging.getLogger(__name__)

# Cache key = (user_id, variant). `variant is None` ⇒ default page-1 view.
_CacheKey = tuple[UUID, str | None]


def _ttl_from_env() -> float:
    """Read default-view TTL from env. Returns `0.0` (cache disabled) on parse
    failure or explicit `FEED_CACHE_TTL_SECONDS=0`."""
    raw = os.environ.get("FEED_CACHE_TTL_SECONDS", "30")
    try:
        return max(0.0, float(raw))
    except ValueError:
        logger.warning("feed_cache_invalid_ttl raw=%s, defaulting to 30s", raw)
        return 30.0


def _personalized_ttl_from_env() -> float:
    """Read personalized-section TTL from env. Returns `0.0` (personalized
    caching disabled) on parse failure or explicit
    `FEED_CACHE_PERSONALIZED_TTL_SECONDS=0`."""
    raw = os.environ.get("FEED_CACHE_PERSONALIZED_TTL_SECONDS", "60")
    try:
        return max(0.0, float(raw))
    except ValueError:
        logger.warning(
            "feed_cache_invalid_personalized_ttl raw=%s, defaulting to 60s", raw
        )
        return 60.0


@dataclass
class _Entry:
    expires_at: float
    payload: bytes


class FeedPageCache:
    """Per-user, per-variant TTL cache with single-flight semantics.

    Thread-safety note: every method assumes it runs on the same asyncio
    event loop. The `_locks` dict is mutated only inside `lock()` which is
    called from coroutines — no cross-thread access.
    """

    def __init__(
        self,
        ttl_seconds: float | None = None,
        personalized_ttl_seconds: float | None = None,
    ) -> None:
        self._ttl = ttl_seconds if ttl_seconds is not None else _ttl_from_env()
        self._personalized_ttl = (
            personalized_ttl_seconds
            if personalized_ttl_seconds is not None
            else _personalized_ttl_from_env()
        )
        self._entries: dict[_CacheKey, _Entry] = {}
        self._locks: dict[_CacheKey, asyncio.Lock] = {}
        self._hits = 0
        self._misses = 0
        self._invalidations = 0
        self._last_flush_at = time.monotonic()

    @property
    def ttl_seconds(self) -> float:
        return self._ttl

    @property
    def personalized_ttl_seconds(self) -> float:
        return self._personalized_ttl

    @property
    def enabled(self) -> bool:
        """True if *any* class of caching is active (default or personalized)."""
        return self.default_enabled or self.personalized_enabled

    @property
    def default_enabled(self) -> bool:
        return self._ttl > 0

    @property
    def personalized_enabled(self) -> bool:
        return self._personalized_ttl > 0

    def _ttl_for(self, variant: str | None) -> float:
        """TTL applied to a key: default-view TTL for `variant is None`, the
        personalized TTL otherwise."""
        return self._ttl if variant is None else self._personalized_ttl

    def lock(self, user_id: UUID, variant: str | None = None) -> asyncio.Lock:
        """Return (or lazily create) the asyncio.Lock for `(user_id, variant)`.

        Public so callers can do the canonical pattern:
            async with FEED_CACHE.lock(user_id, variant):
                hit = FEED_CACHE.get(user_id, variant)
                if hit: return hit
                payload = compute(...)
                FEED_CACHE.put(user_id, payload, variant)
                return payload
        """
        key = (user_id, variant)
        lock = self._locks.get(key)
        if lock is None:
            lock = asyncio.Lock()
            self._locks[key] = lock
        return lock

    def get(self, user_id: UUID, variant: str | None = None) -> bytes | None:
        """Return cached payload for `(user_id, variant)` if fresh, else `None`.
        Updates hit/miss counters."""
        if not self.enabled:
            return None
        entry = self._entries.get((user_id, variant))
        now = time.monotonic()
        if entry is None or entry.expires_at < now:
            self._misses += 1
            self._maybe_flush_telemetry(now)
            return None
        self._hits += 1
        self._maybe_flush_telemetry(now)
        return entry.payload

    def put(self, user_id: UUID, payload: bytes, variant: str | None = None) -> None:
        """Store `payload` for `(user_id, variant)` with the variant's TTL.

        No-op when the relevant TTL class is disabled (default view when
        `FEED_CACHE_TTL_SECONDS=0`, personalized when
        `FEED_CACHE_PERSONALIZED_TTL_SECONDS=0`)."""
        ttl = self._ttl_for(variant)
        if ttl <= 0:
            return
        self._entries[(user_id, variant)] = _Entry(
            expires_at=time.monotonic() + ttl,
            payload=payload,
        )

    def invalidate(self, user_id: UUID) -> None:
        """Drop **all** cached variants for `user_id` (default + personalized).

        Called by every write endpoint. A single call counts as one
        invalidation regardless of how many variants it purged."""
        keys = [key for key in self._entries if key[0] == user_id]
        for key in keys:
            del self._entries[key]
        if keys:
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
            "personalized_ttl_seconds": self._personalized_ttl,
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
            "size=%d hit_rate=%.2f ttl=%.0fs perso_ttl=%.0fs",
            s["hits"],
            s["misses"],
            s["invalidations"],
            s["size"],
            s["hit_rate"],
            s["ttl_seconds"],
            s["personalized_ttl_seconds"],
        )
        self._last_flush_at = now


FEED_CACHE = FeedPageCache()
"""Module-level singleton — import as `from app.services.feed_cache import FEED_CACHE`."""
