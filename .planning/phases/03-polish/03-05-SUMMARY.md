---
phase: 03-polish
plan: 05
subsystem: api, mobile, performance
tags: [selectinload, batch-query, structlog, in-memory-cache, riverpod, sqlalchemy]

# Dependency graph
requires:
  - phase: 03-polish
    provides: DigestSelector & DigestService tests (Plan 04) as regression safety net
  - phase: 03-polish
    provides: Analytics wiring in digest_provider.dart (Plan 03)
provides:
  - Batch-loaded digest API response (eliminates N+1 queries)
  - Performance timing via structlog on all digest endpoints
  - In-memory client-side digest caching (eliminates redundant API calls)
affects: [future recommendation tuning, production monitoring]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Batch content + action state fetching via IN queries instead of per-item loops"
    - "structlog key-value timing on API endpoints (elapsed_ms)"
    - "In-memory cache with date-based invalidation for daily digest"
    - "Optimistic cache updates on user actions with rollback on error"

key-files:
  created: []
  modified:
    - packages/api/app/services/digest_service.py
    - packages/api/app/routers/digest.py
    - apps/mobile/lib/features/digest/providers/digest_provider.dart

key-decisions:
  - "Batch queries over asyncio.gather — SQLAlchemy AsyncSession is not safe for concurrent queries on same session"
  - "In-memory cache only (no Hive/persistent) — digest changes daily, stale risk minimal"
  - "Demoted per-item breakdown logs to debug level — reduces noise in production"
  - "structlog replaces import logging in digest router — fixes tech debt from initial implementation"

patterns-established:
  - "_get_batch_action_states pattern for bulk UserContentStatus lookups"
  - "Cache fields on AsyncNotifier with date-based invalidation"
  - "forceRefresh() method clearing cache before re-fetch"

# Metrics
duration: 5min
completed: 2026-02-08
---

# Phase 3 Plan 5: Performance Optimization (Eager Loading + Caching) Summary

**Batch-loaded digest API eliminating N+1 queries (2*N to 3 queries) with in-memory mobile caching preventing redundant API calls on same-day navigation**

## Performance

- **Duration:** 5 min
- **Started:** 2026-02-08T00:35:54Z
- **Completed:** 2026-02-08T00:41:21Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Eliminated N+1 queries in `_build_digest_response`: batch-fetches all 5 content items and their action states in 3 queries (was 2*5=10 queries before)
- Added `_get_batch_action_states` method for bulk `UserContentStatus` lookups via single `IN` query
- Replaced `import logging` with `structlog` in digest router (tech debt fix) — all digest endpoints now use structured key-value logging
- Added `elapsed_ms` performance timing to GET /digest, POST action, and POST complete endpoints
- Mobile digest provider caches today's digest in memory — navigating away and back skips API call
- Actions optimistically update both state and cache, with rollback on error
- Added `forceRefresh()` method that clears cache and re-fetches from API

## Task Commits

Each task was committed atomically:

1. **Task 1: Optimize backend digest queries and add timing logs** - `8847c42` (perf)
2. **Task 2: Add client-side digest caching in mobile provider** - `5a8a3df` (perf)

## Files Created/Modified
- `packages/api/app/services/digest_service.py` - Batch content+action state fetching in `_build_digest_response`, new `_get_batch_action_states` method
- `packages/api/app/routers/digest.py` - Replaced `import logging` with `structlog`, added `elapsed_ms` timing to all 3 endpoints
- `apps/mobile/lib/features/digest/providers/digest_provider.dart` - In-memory cache fields, cache check in build/loadDigest, optimistic cache updates in actions, `forceRefresh()` method

## Decisions Made
- **Batch queries over asyncio.gather**: SQLAlchemy `AsyncSession` is not designed for concurrent usage on the same session. The real performance win is fewer round trips (batching), not parallelism. Reduced from 2*N queries to 3 fixed queries.
- **In-memory cache only**: No Hive/persistent storage — digest changes daily so stale data risk is minimal. Cache invalidates automatically when date changes.
- **structlog replaces logging module**: The digest router was the last holdout using `import logging` instead of `structlog`. Fixed as part of this optimization.
- **Demoted breakdown rebuild logs**: Per-item `info` logs for breakdown data were noisy in production. Changed to `debug` level. The new batch-level log provides sufficient visibility.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed verbose per-item logging in _build_digest_response**
- **Found during:** Task 1 (batch optimization)
- **Issue:** Each of the 5 digest items logged `info`-level messages for breakdown rebuild, creating 10+ log lines per digest retrieval
- **Fix:** Demoted `rebuilt_breakdown_from_stored_data` (removed — batch log replaces it) and `no_breakdown_data_in_stored_item` to `debug` level
- **Files modified:** packages/api/app/services/digest_service.py
- **Committed in:** 8847c42 (part of Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 bug — excessive logging)
**Impact on plan:** Minor improvement, no scope creep.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 3 Polish is now COMPLETE (all 5 plans executed)
- Digest API performance optimized with batch queries and structured timing logs
- Mobile caching eliminates redundant API calls during session
- 24 regression tests continue to pass (0.25s)
- Ready for Phase 1 remaining work (01-03: verification) or deployment

---
*Phase: 03-polish*
*Completed: 2026-02-08*
