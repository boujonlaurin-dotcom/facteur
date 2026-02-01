---
phase: 02-frontend
plan: 02
subsystem: ui
tags: [flutter, riverpod, haptic, actions, digest]

requires:
  - phase: 01-foundation
    provides: API endpoints for digest actions (POST /api/digest/{id}/action)

provides:
  - Complete action system with Read/Save/Not Interested buttons
  - Digest provider with optimistic updates and completion tracking
  - Not Interested confirmation sheet with source muting
  - Haptic feedback for all actions
  - Visual feedback (card opacity, badges) for processed articles

affects:
  - 02-03 (closure screen needs completion events)
  - 02-04 (feed relegation needs digest navigation)

tech-stack:
  added: []
  patterns:
    - "Optimistic updates in Riverpod provider"
    - "Confirmation bottom sheet pattern for destructive actions"
    - "Haptic feedback integration for action confirmation"
    - "Computed properties in state notifier (processedCount, progress)"

key-files:
  created:
    - apps/mobile/lib/features/digest/widgets/article_action_bar.dart
    - apps/mobile/lib/features/digest/widgets/not_interested_sheet.dart
    - apps/mobile/lib/features/digest/widgets/digest_card.dart
    - apps/mobile/lib/features/digest/screens/digest_screen.dart
    - apps/mobile/lib/features/digest/providers/digest_provider.dart
    - apps/mobile/lib/features/digest/repositories/digest_repository.dart
  modified:
    - apps/mobile/lib/features/digest/models/digest_models.dart

key-decisions:
  - "Used optimistic updates for instant UI feedback on actions"
  - "Not Interested action shows confirmation sheet before muting source"
  - "Haptic feedback varies by action type (medium for read, light for save/dismiss)"
  - "Auto-complete digest when all 5 items processed (read or dismissed)"
  - "Card opacity reduces to 0.6 when article is processed"

patterns-established:
  - "Action handling pattern: DigestCard -> DigestScreen -> digestProvider"
  - "Confirmation sheet pattern for destructive personalization actions"
  - "Computed state properties for progress tracking"
  - "NotificationService integration for action success feedback"

duration: 5min
completed: 2026-02-01
---

# Phase 02 Plan 02: Article Actions Summary

**Article action buttons (Read/Save/Not Interested) with full API integration and Personalization system wiring**

## Performance

- **Duration:** 5 min
- **Started:** 2026-02-01T21:25:00Z
- **Completed:** 2026-02-01T21:30:28Z
- **Tasks:** 7
- **Files created/modified:** 7

## Accomplishments

1. **Digest Repository with Action Endpoints** - Repository methods for applyAction (read/save/not_interested/undo) and completeDigest, following FeedRepository patterns
2. **Digest Provider with State Management** - Riverpod provider with optimistic updates, action handling, completion tracking, and haptic feedback
3. **Article Action Bar Widget** - 3-button bar with animated state changes and proper visual feedback
4. **Not Interested Confirmation Sheet** - Bottom sheet explaining source muting with confirm/cancel actions
5. **Digest Card Integration** - Card with action bar, rank badge, selection reason, and processed state indicators
6. **Digest Screen Implementation** - Complete screen with progress bar, action handling, and navigation to content detail
7. **Haptic Feedback System** - Different haptic intensities for different actions (medium for read, light for save/dismiss, heavy for completion)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add action methods to digest repository** - `5182ae1`
2. **Task 2: Add action state management to provider** - `cd54613`
3. **Task 3: Create article action bar widget** - `60fa958`
4. **Task 4: Create not interested confirmation sheet** - `0dab4e4`
5. **Task 5: Integrate action bar into digest card** - `1fee16d`
6. **Task 6: Wire actions in digest screen** - `43a0590`
7. **Task 7: Add haptic feedback** - (included in Task 2)

## Files Created/Modified

- `apps/mobile/lib/features/digest/repositories/digest_repository.dart` - API client for digest actions
- `apps/mobile/lib/features/digest/providers/digest_provider.dart` - Riverpod state management with actions
- `apps/mobile/lib/features/digest/widgets/article_action_bar.dart` - 3-button action bar
- `apps/mobile/lib/features/digest/widgets/not_interested_sheet.dart` - Confirmation bottom sheet
- `apps/mobile/lib/features/digest/widgets/digest_card.dart` - Digest card with action bar integration
- `apps/mobile/lib/features/digest/screens/digest_screen.dart` - Main digest screen with action handling
- `apps/mobile/lib/features/digest/models/digest_models.dart` - SourceMini model update

## Decisions Made

- **Optimistic updates**: Update UI immediately before API call, rollback on error
- **Confirmation sheet for not_interested**: Prevents accidental source mutes
- **Haptic feedback by action type**: Medium for read (primary action), light for save/dismiss
- **Auto-completion**: Digest automatically completes when all items processed
- **Visual feedback**: Card opacity reduces, "Lu"/"Masqué" badges appear when processed

## Deviations from Plan

**1. [Rule 3 - Blocking] SourceMini model already existed with Freezed**
- **Found during:** Task 5 (DigestCard creation)
- **Issue:** Existing digest_models.dart from 02-01 used Freezed, SourceMini had no id field
- **Fix:** Used contentId as source id fallback in DigestScreen _openDetail method
- **Files modified:** apps/mobile/lib/features/digest/screens/digest_screen.dart
- **Committed in:** 43a0590

**2. [Rule 2 - Missing Critical] Added missing model fields for navigation**
- **Found during:** Task 6 (DigestScreen implementation)
- **Issue:** Navigation to content detail requires Source model with type parameter
- **Fix:** Added _mapSourceType method to convert ContentType to SourceType
- **Files modified:** apps/mobile/lib/features/digest/screens/digest_screen.dart
- **Committed in:** 43a0590

---

**Total deviations:** 2 auto-fixed (2 blocking)
**Impact on plan:** Both necessary for correct integration with existing navigation system

## Issues Encountered

- **Freezed model compatibility**: Existing digest_models.dart from 02-01 used Freezed. Worked around by using existing models and adding helper methods where needed.

## Next Phase Readiness

### Ready for 02-03: Closure Screen
- Digest completion is detected and triggers automatically
- Streak info available in digest state
- Haptic feedback for completion already implemented

### Ready for 02-04: Feed Relegation
- Digest screen is the main entry point
- Navigation to content detail already works
- Feed screen remains accessible for "Explorer plus" navigation

## Success Criteria Verification

- [x] Each digest card shows 3 action buttons (Read, Save, Not Interested)
- [x] Read action marks article as consumed with visual feedback (opacity 0.6, "Lu" badge)
- [x] Save action bookmarks article and shows active state (primary color)
- [x] Not Interested shows confirmation sheet and mutes source
- [x] Actions have immediate visual feedback (button state, card opacity)
- [x] API calls implemented for all actions
- [x] Notifications confirm action success ("Article marqué comme lu", etc.)
- [x] Haptic feedback provides tactile confirmation (light/medium/heavy)

---
*Phase: 02-frontend*
*Completed: 2026-02-01*
