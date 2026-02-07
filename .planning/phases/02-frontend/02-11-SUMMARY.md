---
phase: 02-frontend
plan: 11
subsystem: api
tags: [digest, scoring, transparency, pydantic, fastapi]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: "DigestSelector service with scoring infrastructure"
  - phase: 02-frontend
    provides: "Feed scoring transparency pattern from content.py"
provides:
  - DigestScoreBreakdown and DigestRecommendationReason Pydantic schemas
  - Full scoring contribution capture in digest selection
  - Enhanced API response with detailed reasoning
  - Backward-compatible reason field preservation
affects:
  - Frontend digest UI (Plan 02-12)
  - Mobile app "Pourquoi cet article?" feature

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "ScoreContribution pattern matching feed implementation"
    - "Optional backward-compatible field addition"
    - "JSONB storage for complex breakdown data"

key-files:
  created: []
  modified:
    - packages/api/app/schemas/digest.py
    - packages/api/app/services/digest_selector.py
    - packages/api/app/services/digest_service.py

key-decisions:
  - "Matched feed's ScoreContribution/Reason structure for UI consistency"
  - "Preserved legacy 'reason' string for backward compatibility"
  - "Stored breakdown in JSONB to enable retrieval of full scoring history"
  - "Derived top reason intelligently from highest positive contribution"

patterns-established:
  - "Algorithmic transparency via detailed scoring breakdown"
  - "5-layer contribution capture: Core, Recency, Topics, Preferences, Quality"

# Metrics
duration: 25min
completed: 2026-02-06
---

# Phase 2 Plan 11: Digest Scoring Transparency Summary

**Extended digest API to return detailed scoring breakdown matching feed's RecommendationReason structure, enabling "Pourquoi cet article?" feature with full algorithmic transparency.**

## Performance

- **Duration:** 25 min
- **Started:** 2026-02-06T17:11:55Z
- **Completed:** 2026-02-06T17:36:55Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments

- Added DigestScoreBreakdown schema with label, points, and is_positive fields
- Added DigestRecommendationReason schema with label, score_total, and breakdown array
- Updated DigestItem to include both legacy 'reason' and new 'recommendation_reason' fields
- Modified DigestSelector._score_candidates() to capture all 5 scoring layer contributions
- Implemented recency bonus breakdown with 6 tiers (<6h to 120-168h)
- Captured CoreLayer contributions: Theme match (+70), Trusted source (+40), Custom source (+10)
- Captured ArticleTopicLayer: Topic matches (+60, max 2), Subtopic precision (+20)
- Captured StaticPreferenceLayer: Format match (+15)
- Captured QualityLayer: Curated source (+10), Low reliability penalty (-30)
- Updated _create_digest_record() to store breakdown in JSONB
- Added _determine_top_reason() helper to extract most significant positive reason
- Enhanced _build_digest_response() to rebuild recommendation_reason from stored data

## Task Commits

1. **Task 1: Extend Pydantic Schemas with Breakdown Models** - `8f4be42` (feat)
2. **Task 2: Capture Scoring Contributions in DigestSelector** - `1376b99` (feat)
3. **Task 3: Update API Response with Enhanced Reasoning** - `ac88871` (feat)

**Plan metadata:** (pending final commit)

## Files Created/Modified

- `packages/api/app/schemas/digest.py` - Added DigestScoreBreakdown, DigestRecommendationReason, updated DigestItem
- `packages/api/app/services/digest_selector.py` - Enhanced _score_candidates() with breakdown capture, updated DigestItem dataclass
- `packages/api/app/services/digest_service.py` - Added _determine_top_reason(), enhanced _build_digest_response()

## Decisions Made

- **Matched feed pattern:** Used same ScoreContribution structure as content.py for UI consistency
- **Backward compatibility:** Kept existing 'reason' string field to avoid breaking existing clients
- **JSONB storage:** Stored breakdown array in database to enable historical analysis
- **Intelligent top reason:** Derived label from highest positive contribution with category-specific formatting

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- Pre-existing LSP type errors in SQLAlchemy queries (not related to this plan)
- Type checking issues with ReliabilityScore comparison (pre-existing in codebase)

## Next Phase Readiness

Ready for Plan 02-12: Frontend UI integration of "Pourquoi cet article?" feature
- Backend returns full scoring transparency
- API response includes breakdown array with 4-8 items per article
- Frontend can now display detailed scoring modal matching feed pattern

---
*Phase: 02-frontend*
*Completed: 2026-02-06*
