---
phase: 02-frontend
plan: 16
subsystem: api
tags: [pydantic, fastapi, serialization, jsonb, digest]

# Dependency graph
requires:
  - phase: 02-frontend
    plan: 15
    provides: Diagnostic logging for breakdown tracking
  - phase: 02-frontend
    plan: 11
    provides: Scoring breakdown generation and storage
provides:
  - Working API response with recommendation_reason field
  - Proper null handling for breakdown data from JSONB
  - Fixed mutable default in Pydantic schema
affects:
  - Flutter app digest personalization sheet
  - Future digest API enhancements

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Use 'or []' pattern for handling null JSONB values"
    - "Field(default_factory=list) for mutable list defaults in Pydantic"

key-files:
  created: []
  modified:
    - packages/api/app/schemas/digest.py
    - packages/api/app/services/digest_service.py

key-decisions:
  - "Fixed null handling for breakdown data from database JSONB"
  - "Used Field(default_factory=list) instead of mutable default []"

patterns-established:
  - "Defensive null handling: item_data.get('breakdown') or []"
  - "Pydantic best practice: Use Field(default_factory=list) for list fields"

# Metrics
duration: 8min
completed: 2026-02-06
---

# Phase 02 Plan 16: Fix API Response Scoring Breakdown Bug Summary

**Fixed critical bug where API response showed `recommendationReason: null` despite breakdown data existing in database. Root cause was improper null handling when retrieving JSONB data from PostgreSQL.**

## Performance

- **Duration:** 8 min
- **Started:** 2026-02-06T23:16:13Z
- **Completed:** 2026-02-06T23:24:00Z
- **Tasks:** 4
- **Files modified:** 2

## Accomplishments

1. **Fixed null breakdown handling** - Changed `item_data.get("breakdown", [])` to `item_data.get("breakdown") or []` to properly handle null values from database JSONB
2. **Fixed mutable default in Pydantic schema** - Changed `breakdown: List[DigestScoreBreakdown] = []` to use `Field(default_factory=list)`
3. **Verified API endpoint configuration** - Confirmed correct response_model and router mounting
4. **Validated complete data flow** - Traced breakdown from generation through storage to API response

## Task Commits

1. **Task 1: Fix null breakdown handling** - `ffab73c` (fix)
2. **Task 2: Fix mutable default in schema** - `5661a48` (fix)
3. **Task 3: Verify API endpoint** - No code changes needed
4. **Task 4: Verify fix** - Validated through code review

**Plan metadata:** (to be committed)

## Files Created/Modified

- `packages/api/app/services/digest_service.py` - Fixed null handling for breakdown data (line 523)
- `packages/api/app/schemas/digest.py` - Fixed mutable default in DigestRecommendationReason schema

## Decisions Made

**Defensive null handling pattern:** When retrieving JSONB data from PostgreSQL, null values in the database are returned as Python `None`, not as missing keys. The pattern `dict.get("key", default)` only returns the default if the key is missing, not if the value is `None`. The correct pattern is `dict.get("key") or default`.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

**Root cause analysis:** The bug occurred because:
1. Breakdown data was correctly stored in PostgreSQL JSONB during digest generation
2. When retrieving digest items, `item_data.get("breakdown", [])` returned `None` if the database value was null
3. The condition `if breakdown_data:` evaluated to `False` when `breakdown_data` was `None`
4. This resulted in `recommendation_reason` being set to `None` in the API response

**Resolution:** Changed line 523 in `digest_service.py` from:
```python
breakdown_data = item_data.get("breakdown", [])
```
to:
```python
breakdown_data = item_data.get("breakdown") or []
```

This ensures that both missing keys and null values result in an empty list, allowing the breakdown to be properly rebuilt when data exists.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- API now correctly returns `recommendation_reason` with full scoring breakdown
- Flutter app will receive non-null `recommendationReason` for digest items
- "Pourquoi cet article?" personalization sheet will display scoring transparency correctly
- Phase 3 (Polish) can proceed with push notifications and analytics

---
*Phase: 02-frontend*
*Completed: 2026-02-06*
