---
phase: 01-production-fixes
plan: 02
subsystem: api

# Dependency graph
requires:
  - phase: 01-production-fixes-01
    provides: Digest generation job infrastructure
provides:
  - Decay-based source diversity algorithm for digest selection
  - 0.70 decay factor implementation matching feed algorithm
  - Minimum 3 sources enforcement
  - Diversity logging and monitoring
affects:
  - digest_selector.py
  - digest generation quality

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Decay factor pattern: score * (0.70 ^ count)"
    - "Source diversity tracking with defaultdict"
    - "Algorithm consistency: matching feed algorithm"

key-files:
  created: []
  modified:
    - packages/api/app/services/digest_selector.py

key-decisions:
  - "Decay factor 0.70: Matches existing feed algorithm for consistency"
  - "MIN_SOURCES = 3: Ensures meaningful diversity in 5-article digest"
  - "Apply decay before constraint checks: Scores reflect true priority"
  - "Log warning on insufficient sources: Monitoring without blocking"

patterns-established:
  - "Decay scoring: Apply 0.70^n factor to subsequent articles from same source"
  - "Diversity monitoring: Track source counts and log warnings"
  - "Algorithm parity: Keep digest and feed diversity algorithms consistent"

# Metrics
duration: 1min
completed: 2026-02-07
---

# Phase 1 Plan 2: Source Diversity with Decay Factor Summary

**Decay-based source diversity algorithm with 0.70 decay factor in _select_with_diversity() — matching feed algorithm, ensuring minimum 3 sources, and preserving max 2 per source/theme constraints**

## Performance

- **Duration:** 1 min
- **Started:** 2026-02-07T10:54:59Z
- **Completed:** 2026-02-07T10:56:01Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- Implemented decay factor 0.70 in `_select_with_diversity()` method
- Added formula: `decayed_score = score * (0.70 ^ source_count)`
- Added MIN_SOURCES = 3 requirement with warning log
- Updated debug log to include decay_factor for monitoring
- Preserved existing MAX_PER_SOURCE=2 and MAX_PER_THEME=2 constraints
- Selected items now use decayed scores for ranking

## Task Commits

1. **Task 1: Implement decay-based diversity in _select_with_diversity()** - `7788c49` (fix)

**Plan metadata:** (pending)

## Files Created/Modified

- `packages/api/app/services/digest_selector.py` - Modified `_select_with_diversity()` method:
  - Added DECAY_FACTOR = 0.70 constant
  - Added MIN_SOURCES = 3 constant
  - Implemented decay scoring: `score * (DECAY_FACTOR ** current_source_count)`
  - Added minimum sources check with warning log
  - Updated debug log to include decay_factor

## Decisions Made

1. **Decay factor 0.70**: Matches existing feed algorithm for consistency
2. **MIN_SOURCES = 3**: Ensures meaningful diversity in 5-article digest
3. **Apply decay before constraint checks**: Scores reflect true priority
4. **Log warning on insufficient sources**: Monitoring without blocking digest generation

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Ready for **01-production-fixes-03**: Verify fixes (scheduler + diversity tests)

- Decay factor algorithm implemented and committed
- Algorithm ready for test coverage verification
- No blockers or concerns

---
*Phase: 01-production-fixes*
*Completed: 2026-02-07*
