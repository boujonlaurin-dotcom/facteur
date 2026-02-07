---
phase: 02-frontend
plan: 15
subsystem: api
tags: [structlog, diagnostics, logging, scoring-transparency]

requires:
  - phase: 02-11
    provides: Scoring breakdown generation in DigestSelector

provides:
  - Diagnostic logging for breakdown storage tracking
  - Verification that force regenerate creates digest with breakdown data
  - Logs distinguish between old digests (no breakdown) and new digests (with breakdown)

affects:
  - Digest personalization sheet display
  - Debuggability of scoring transparency feature

tech-stack:
  added: []
  patterns:
    - "Structured logging with structlog for observability"
    - "Warning logs for missing data scenarios"

key-files:
  created: []
  modified:
    - packages/api/app/services/digest_service.py

key-decisions:
  - "Added WARNING level for missing breakdown to easily identify old digests"
  - "Included content_title preview in logs for easier correlation"
  - "Added item_type logging to distinguish EmergencyItem from scored items"

patterns-established:
  - "Diagnostic logging: Use INFO for successful operations, WARNING for missing data"

# Metrics
duration: 5 min
completed: 2026-02-06
---

# Phase 02: Plan 15 - Fix Missing Scoring Breakdown Data

**Diagnostic logging added to digest service to track breakdown generation, storage, and retrieval for debugging scoring transparency**

## Performance

- **Duration:** 5 min
- **Started:** 2026-02-06T23:00:00Z
- **Completed:** 2026-02-06T23:00:55Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- Added comprehensive logging to `_create_digest_record()` for breakdown storage tracking
- Added detailed logging to `_build_digest_response()` for breakdown retrieval tracking
- Logs now distinguish between old digests (generated before 02-11) and new digests with breakdown data
- User can force regenerate digest via existing endpoint to get fresh data with breakdown

## Task Commits

1. **Task 1: Add diagnostic logging for breakdown tracking** - `8f75dcf` (feat)

## Files Created/Modified

- `packages/api/app/services/digest_service.py` - Added 4 logging statements:
  - INFO log when breakdown is stored (lines 417-423)
  - WARNING log when breakdown is missing during storage (lines 433-438)
  - INFO log when breakdown is rebuilt from stored data (lines 525-530)
  - WARNING log when stored item has no breakdown data (lines 532-537)

## Decisions Made

- Used WARNING level for missing breakdown to make it easy to identify old digests in log aggregation
- Included truncated content_title (first 50 chars) for easier debugging and correlation
- Added item_type field to distinguish between EmergencyItem (fallback) and properly scored items

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Diagnostic logging is in place for debugging
- User can force regenerate to get fresh digest with breakdown data
- Old digests will show "Information non disponible" until regenerated (expected behavior)
- Ready for Phase 03 - Polish

---
*Phase: 02-frontend*
*Completed: 2026-02-06*
