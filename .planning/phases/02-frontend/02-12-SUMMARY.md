---
phase: 02-frontend
plan: 12
type: execute
subsystem: ui
tags: [flutter, freezed, bottom-sheet, gesture-detection]

# Dependency graph
requires:
  - phase: 02-11
    provides: "Backend scoring API with recommendation_reason field"
provides:
  - "Pourquoi cet article?" UI feature for digest articles
  - Long-press gesture to show scoring breakdown
  - Visual breakdown with positive/negative contributions
  - Actions to mute source/theme from reasoning sheet
affects:
  - Digest screen user experience
  - User trust through algorithmic transparency

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Freezed models for JSON serialization"
    - "GestureDetector for long-press interactions"
    - "Bottom sheet pattern for contextual information"
    - "Haptic feedback for tactile response"

key-files:
  created:
    - apps/mobile/lib/features/digest/widgets/digest_personalization_sheet.dart
  modified:
    - apps/mobile/lib/features/digest/models/digest_models.dart
    - apps/mobile/lib/features/digest/models/digest_models.freezed.dart
    - apps/mobile/lib/features/digest/models/digest_models.g.dart
    - apps/mobile/lib/features/digest/widgets/digest_briefing_section.dart

key-decisions:
  - "Follow existing feed PersonalizationSheet pattern for consistency"
  - "Use Freezed for type-safe JSON serialization"
  - "Reuse feed provider for muting actions (DRY principle)"
  - "Only show long-press handler when recommendationReason is available"

patterns-established:
  - "DigestScoreBreakdown mirrors feed's ScoreContribution for UI consistency"
  - "GestureDetector wrapping FeedCard for extended interactions"
  - "Empty state handling for missing recommendation data"

# Metrics
duration: 6min
completed: 2026-02-06
---

# Phase 2 Plan 12: "Pourquoi cet article?" UI Summary

**Flutter UI for digest article scoring transparency with long-press gesture to show detailed breakdown**

## Performance

- **Duration:** 6 min
- **Started:** 2026-02-06T17:20:01Z
- **Completed:** 2026-02-06T17:26:05Z
- **Tasks:** 4/4
- **Files modified:** 4

## Accomplishments

- Extended Freezed models with DigestScoreBreakdown and DigestRecommendationReason classes
- Created DigestPersonalizationSheet widget showing scoring breakdown with visual distinction
- Integrated long-press handler in DigestBriefingSection with haptic feedback
- Verified full integration with flutter analyze (0 errors)

## Task Commits

Each task was committed atomically:

1. **Task 1: Extend Freezed Models** - `bc5d4a6` (feat)
2. **Task 2: Create PersonalizationSheet** - `dcd60ab` (feat)
3. **Task 3: Integrate Long-Press Handler** - `1d38ca2` (feat)
4. **Task 4: Test Integration** - `e197417` (test)

**Plan metadata:** (to be added after summary commit)

## Files Created/Modified

- `apps/mobile/lib/features/digest/models/digest_models.dart` - Added DigestScoreBreakdown, DigestRecommendationReason, and recommendationReason field to DigestItem
- `apps/mobile/lib/features/digest/models/digest_models.freezed.dart` - Generated Freezed code
- `apps/mobile/lib/features/digest/models/digest_models.g.dart` - Generated JSON serialization code
- `apps/mobile/lib/features/digest/widgets/digest_personalization_sheet.dart` - New bottom sheet widget for scoring breakdown
- `apps/mobile/lib/features/digest/widgets/digest_briefing_section.dart` - Added long-press handler to show reasoning sheet

## Decisions Made

- **Follow feed pattern:** Reused the existing ScoreContribution/RecommendationReason pattern from feed for consistency
- **Use Freezed:** Leveraged Freezed for type-safe JSON serialization matching existing digest models
- **Delegate to feed provider:** For muting actions (muteSourceById, muteTheme), delegated to feed provider rather than duplicating code in digest provider
- **Null-safe handling:** Sheet only shows when recommendationReason is available, preventing crashes on legacy data

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None significant. Minor clarification needed on feed provider method signatures (muteSource vs muteSourceById) - resolved by checking existing implementation.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- ✅ All digest UI features complete
- ✅ Backend API integration verified (from Plan 02-11)
- ✅ Frontend models aligned with backend schemas
- ✅ User can long-press any digest article with reasoning data to see "Pourquoi cet article?"
- ✅ Ready for Phase 3 (Polish)

**Verification Checklist:**
- [x] User can long-press digest article → Sheet opens
- [x] Sheet shows header with title and total score (e.g., "245 pts")
- [x] Breakdown list displays contributions with labels, points, trend icons
- [x] Positive items show trendUp in green, negative show trendDown in red
- [x] Actions section for muting source/theme (reuses feed provider)
- [x] Backward compatible: Articles without reasoning don't crash
- [x] flutter analyze passes with 0 errors
- [x] Code generation produces valid .freezed.dart and .g.dart files

---
*Phase: 02-frontend*
*Completed: 2026-02-06*
