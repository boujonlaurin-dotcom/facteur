---
phase: 02-frontend
plan: 09
subsystem: api
tags: [sqlalchemy, async, eager-loading, selectinload, greenlet]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: DigestService with _build_digest_response() method
provides:
  - Eager loading pattern for content.source relationship
  - Fix for MissingGreenlet error in async context
  - Working digest API without lazy loading crashes
affects:
  - digest API endpoint
  - _build_digest_response() method
  - Content.source relationship access

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "selectinload for eager loading async SQLAlchemy relationships"
    - "Replace session.get() with select().options() for relationship loading"

key-files:
  created: []
  modified:
    - packages/api/app/services/digest_service.py

key-decisions:
  - "Use selectinload(Content.source) instead of session.get() to prevent lazy loading in async context"

patterns-established:
  - "Always use eager loading (selectinload) when accessing relationships in async SQLAlchemy code"

# Metrics
duration: 1min
completed: 2026-02-04
---

# Phase 2 Plan 9: Fix MissingGreenlet Error with Eager Loading

**Fixed MissingGreenlet error by adding selectinload eager loading for content.source relationship in digest_service.py**

## Performance

- **Duration:** 1 min
- **Started:** 2026-02-04T12:07:42Z
- **Completed:** 2026-02-04T12:08:47Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- Added `from sqlalchemy.orm import selectinload` import at top level of digest_service.py
- Fixed TWO locations with MissingGreenlet error:
  1. `_build_digest_response()` (line ~387) - Replaced `session.get(Content, content_id)` with eager loading query
  2. `_trigger_personalization_mute()` (line ~487) - Added selectinload for content.source relationship
- Fixed MissingGreenlet error that occurred when accessing `content.source` in async context
- Applied same eager loading pattern already used in `_get_emergency_candidates()` method
- All existing error handling and warning logging preserved

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix eager loading in _build_digest_response()** - `40433d8` (fix)
2. **Task 2: Fix eager loading in _trigger_personalization_mute()** - `670e49f` (fix) - *Follow-up fix after testing revealed second location*

## Files Created/Modified

- `packages/api/app/services/digest_service.py` - Added selectinload import and replaced lazy loading with eager loading in TWO methods:
  - `_build_digest_response()` (line ~387)
  - `_trigger_personalization_mute()` (line ~487)

## Decisions Made

None - followed plan as specified. The fix was straightforward application of the existing pattern used elsewhere in the codebase.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

**Initial fix incomplete** - The first implementation only fixed `_build_digest_response()` but missed `_trigger_personalization_mute()` which also accessed `content.source` after `session.get()`. This caused the MissingGreenlet error to persist when users marked articles as "not interested" (which triggers the personalization mute). 

**Root cause:** Insufficient code review - only searched for one pattern occurrence instead of auditing all Content.source accesses in the file.

**Resolution:** Second commit (670e49f) applied the same fix to `_trigger_personalization_mute()`. All `session.get(Content, content_id)` calls that access `content.source` have now been replaced with eager loading queries.

## Next Phase Readiness

- MissingGreenlet error resolved for digest API
- Content.source relationship now loads eagerly without triggering lazy loading
- Backend ready for frontend digest screen testing

---
*Phase: 02-frontend*
*Completed: 2026-02-04*
