---
phase: 03-polish
plan: 03
subsystem: analytics, mobile, api
tags: [analytics, content-interaction, digest-session, metrics, jsonb, riverpod]

# Dependency graph
requires:
  - phase: 03-polish
    provides: Unified analytics schemas and service methods (Plan 02)
provides:
  - Digest flow fully instrumented with content_interaction events
  - Digest session tracking on closure with breakdown stats
  - GET /analytics/digest-metrics endpoint for KPI querying
affects: [03-05 performance optimization, future recommendation tuning]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Analytics events fire after API success, never block user actions"
    - "JSONB text() aggregation for analytics queries (no ORM filtering)"
    - "Duplicate-prevention flag for one-shot analytics events"

key-files:
  created: []
  modified:
    - apps/mobile/lib/features/digest/providers/digest_provider.dart
    - apps/mobile/lib/features/digest/screens/closure_screen.dart
    - packages/api/app/services/analytics_service.py
    - packages/api/app/routers/analytics.py

key-decisions:
  - "Map UI 'not_interested' action to analytics 'dismiss' (semantic alignment)"
  - "Silent failure for analytics — errors never block user interactions"
  - "JSONB text() queries for aggregation performance over ORM filtering"
  - "Pass count calculated as total minus read/saved/dismissed in closure"

patterns-established:
  - "Analytics tracking in provider after API success, not in UI layer"
  - "One-shot event tracking with boolean flag to prevent duplicates"

# Metrics
duration: 3min
completed: 2026-02-08
---

# Phase 3 Plan 3: Wire Analytics into Digest + Metrics Endpoint Summary

**Digest flow instrumented with unified content_interaction events (read/save/dismiss) and digest_session tracking on closure, plus GET /analytics/digest-metrics backend endpoint for KPI aggregation**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-08T00:28:45Z
- **Completed:** 2026-02-08T00:32:34Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Digest provider fires `trackContentInteraction` with surface='digest' on read, save, and dismiss actions
- Maps UI action 'not_interested' to analytics 'dismiss' for semantic consistency
- Closure screen fires `trackDigestSession` once on completion with full breakdown (read/saved/dismissed/passed)
- Backend GET /analytics/digest-metrics returns completion_rate, avg_closure_time_seconds, total_closures, and interaction breakdown by action
- JSONB text() SQL for aggregation performance

## Task Commits

Each task was committed atomically:

1. **Task 1: Wire content_interaction events into digest provider and screens** - `810043c` (feat)
2. **Task 2: Add backend digest metrics query helpers and endpoint** - `2d5d41c` (feat)

## Files Created/Modified
- `apps/mobile/lib/features/digest/providers/digest_provider.dart` - Added _trackContentInteraction method, fires on read/save/dismiss via applyAction
- `apps/mobile/lib/features/digest/screens/closure_screen.dart` - Added _trackDigestSession method, fires once on completion data load
- `packages/api/app/services/analytics_service.py` - Added get_digest_metrics and get_interaction_breakdown methods with JSONB aggregation
- `packages/api/app/routers/analytics.py` - Added GET /digest-metrics endpoint with auth protection

## Decisions Made
- Mapped 'not_interested' UI action to 'dismiss' analytics action (semantic alignment with unified schema)
- Topics passed as empty list since DigestItem model doesn't carry topics field (future: add topics to digest API response)
- Pass count in digest_session calculated as total minus acted-upon articles (read+saved+dismissed)
- Silent failure pattern: analytics errors caught and logged but never block user flow

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Digest analytics fully wired — all article actions tracked as content_interaction events
- Session-level tracking fires on closure with complete breakdown
- Backend metrics endpoint ready for dashboard or monitoring integration
- Ready for Plan 03-05 (performance optimization)

---
*Phase: 03-polish*
*Completed: 2026-02-08*
