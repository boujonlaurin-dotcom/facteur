---
phase: 03-polish
plan: 02
subsystem: api, analytics
tags: [pydantic, analytics, content-interaction, unified-events, dart, flutter]

# Dependency graph
requires:
  - phase: 01-production-fixes
    provides: Working digest system with scheduler and diversity
provides:
  - Pydantic schemas for unified content_interaction, digest_session, feed_session events
  - Backend AnalyticsService methods (log_content_interaction, log_digest_session, log_feed_session)
  - Mobile AnalyticsService unified tracking methods (trackContentInteraction, trackDigestSession, trackFeedSession)
affects: [03-03 analytics wiring, 03-05 performance optimization]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Unified content_interaction event type with surface field (GAFAM pattern)"
    - "Forward-compatible nullable atomic_themes field for Camembert"
    - "Deprecation markers on legacy analytics methods (clean break strategy)"

key-files:
  created:
    - packages/api/app/schemas/analytics.py
  modified:
    - packages/api/app/services/analytics_service.py
    - apps/mobile/lib/core/services/analytics_service.dart

key-decisions:
  - "Single content_interaction event type with action+surface enums per CONTEXT.md"
  - "Clean break with deprecation: old methods marked @deprecated, new unified methods added alongside"
  - "Forward-compatible atomic_themes field (nullable) for future Camembert enrichment"

patterns-established:
  - "Unified analytics: one event type per domain (content_interaction) with context fields, not separate event types per surface"
  - "Pydantic schemas for event payload validation before storage"

# Metrics
duration: 3min
completed: 2026-02-08
---

# Phase 3 Plan 2: Unified Analytics Schema Summary

**Pydantic schemas for unified content_interaction events (read/save/dismiss/pass across feed/digest surfaces) with backend + mobile service methods, forward-compatible for Camembert atomic themes**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-08T00:11:57Z
- **Completed:** 2026-02-08T00:14:46Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Created unified `content_interaction` Pydantic schema with `InteractionAction` (read/save/dismiss/pass) and `InteractionSurface` (feed/digest) enums
- Added `DigestSessionPayload` and `FeedSessionPayload` for session-level events
- Extended backend `AnalyticsService` with `log_content_interaction`, `log_digest_session`, `log_feed_session` methods
- Extended mobile `AnalyticsService` with `trackContentInteraction`, `trackDigestSession`, `trackFeedSession` methods
- Forward-compatible `atomic_themes` field (nullable) ready for Camembert enrichment
- Legacy methods preserved with `@deprecated` markers — no breaking changes

## Task Commits

Each task was committed atomically:

1. **Task 1: Create backend Pydantic schemas and extend AnalyticsService** - `8899994` (feat)
2. **Task 2: Extend mobile AnalyticsService with unified tracking methods** - `f1879cf` (feat)

## Files Created/Modified
- `packages/api/app/schemas/analytics.py` - Pydantic schemas: ContentInteractionPayload, DigestSessionPayload, FeedSessionPayload, InteractionAction, InteractionSurface enums
- `packages/api/app/services/analytics_service.py` - Added log_content_interaction, log_digest_session, log_feed_session methods
- `apps/mobile/lib/core/services/analytics_service.dart` - Added trackContentInteraction, trackDigestSession, trackFeedSession; deprecated old methods

## Decisions Made
- Used `list[str]` not `List[str]` per Python 3.12 constraint
- Clean break with deprecation for legacy methods (old methods marked `@deprecated`, not removed)
- Session-level events remain surface-specific (different shapes for digest vs feed sessions) but reference same session_id

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Unified analytics schemas and service methods ready for wiring into screens (Plan 03-03)
- Backend POST /analytics/events endpoint already accepts the new event types via JSONB (no migration needed)
- Note: Pre-existing pubspec.yaml conflict from Plan 03-01 (flutter_local_notifications vs timezone version) — not related to this plan, needs resolution in Plan 03-01

---
*Phase: 03-polish*
*Completed: 2026-02-08*
