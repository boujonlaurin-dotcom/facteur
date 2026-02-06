---
phase: 02-frontend
plan: 14
type: execute
subsystem: ui
requires:
  - 02-11 (Digest Scoring Transparency Backend)
  - 02-12 (Pourquoi cet article? UI)
  - 02-13 (Not Interested Confirmation Flow Fix)
provides:
  - Unified personalization pattern across Digest and Feed
  - Consistent "Pourquoi cet article?" UX
  - Simplified code (removed separate confirmation sheet)
affects:
  - Future personalization features
  - User experience consistency across screens
---

# Phase 2 Plan 14: Digest Personalization Unification

## Summary

Aligned Digest personalization UI with Feed personalization to have ONE consistent system across the platform. Removed the separate confirmation + personalization sheets flow and unified them into a single "Pourquoi cet article?" sheet with scoring breakdown and personalization options combined.

## One-Liner

Unified Digest and Feed personalization into single "Pourquoi cet article?" sheet with scoring + personalization options.

## Completed Tasks

| # | Task | Status | Commit |
|---|------|--------|--------|
| 1 | Remove separate confirmation flow and create unified Digest personalization | ✅ Complete | 2be5e20 |
| 2 | Test and verify Feed pattern match | ✅ Complete | 2be5e20 |

## Files Modified

- **Deleted:** `apps/mobile/lib/features/digest/widgets/not_interested_confirmation_sheet.dart` (156 lines removed)
- **Modified:** `apps/mobile/lib/features/digest/screens/digest_screen.dart`
  - Removed import of `not_interested_confirmation_sheet.dart`
  - Updated `_handleNotInterested()` to apply action immediately
  - Shows unified `DigestPersonalizationSheet` directly (no confirmation step)

## Key Changes

### Before (Two-step UX):
1. Tap "moins voir..." → Show confirmation sheet "Masquer cet article?"
2. Tap confirm → Apply action → Optionally show personalization sheet

### After (Unified UX):
1. Tap "moins voir..." → Apply action immediately
2. Show unified sheet with:
   - Scoring breakdown ("Pourquoi cet article?")
   - Personalization options (mute source/theme)

### Code Simplification:
```dart
// New simplified flow
void _handleNotInterested(DigestItem item) {
  HapticFeedback.lightImpact();
  
  // Apply action immediately
  ref.read(digestProvider.notifier).applyAction(
    item.contentId,
    'not_interested',
  );
  
  // Show unified sheet (scoring + personalization)
  _showPersonalizationSheet(item);
}
```

## Visual Design Match

The `DigestPersonalizationSheet` already matched Feed's `PersonalizationSheet`:
- ✅ Same header: Question icon + "Pourquoi cet article?" + "{total} pts" badge
- ✅ Same breakdown list: trendUp/trendDown icons with labels and points
- ✅ Same divider and "PERSONNALISER MON FLUX" section header
- ✅ Same action items: eyeSlash icon with mute source/theme options
- ✅ Same padding (top: 24, bottom: 40, horizontal: 20)
- ✅ Same border radius (20px top)
- ✅ Same background color (backgroundSecondary)

## Decisions Made

| Decision | Rationale |
|----------|-----------|
| Apply action immediately (no confirmation) | Matches Feed behavior; simplifies UX |
| Keep DigestPersonalizationSheet separate | Already matches Feed pattern; no need to share code yet |
| Use feedProvider for personalization actions | Reuses existing personalization logic (DRY) |

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## Verification

- ✅ `not_interested_confirmation_sheet.dart` deleted
- ✅ `DigestPersonalizationSheet` shows unified sheet matching Feed pattern
- ✅ `_handleNotInterested` applies action immediately and shows unified sheet
- ✅ flutter analyze passes with 0 new errors

## Next Phase Readiness

Phase 2 Frontend is now complete with 13/13 plans executed. Ready for Phase 3 (Polish):
- Morning push notifications (8am digest ready)
- Analytics integration (MoC completion tracking)
- Performance optimization (<500ms load time)

## Performance Metrics

- Duration: ~5 minutes
- Files modified: 2
- Lines removed: 148
- Code complexity: Reduced (removed separate confirmation flow)

---
*Completed: 2026-02-06*
