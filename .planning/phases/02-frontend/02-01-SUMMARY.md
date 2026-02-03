---
phase: 02-frontend
plan: 01
subsystem: ui
tags: [flutter, riverpod, freezed, digest]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: API endpoints at /api/digest
provides:
  - Digest models with Freezed
  - Digest repository for API calls
  - Riverpod state management
  - Progress bar widget
  - Digest card widget
  - Digest screen UI
  - Route configuration
affects:
  - 02-02 (article actions)
  - 02-03 (closure screen)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Freezed models with JSON serialization"
    - "Riverpod AsyncNotifier for state management"
    - "Repository pattern for API calls"
    - "FeedCard visual reuse pattern"

key-files:
  created:
    - apps/mobile/lib/features/digest/models/digest_models.dart
    - apps/mobile/lib/features/digest/repositories/digest_repository.dart
    - apps/mobile/lib/features/digest/providers/digest_provider.dart
    - apps/mobile/lib/features/digest/widgets/progress_bar.dart
    - apps/mobile/lib/features/digest/widgets/digest_card.dart
    - apps/mobile/lib/features/digest/screens/digest_screen.dart
  modified:
    - apps/mobile/lib/config/routes.dart

key-decisions:
  - "Reused FeedCard visual patterns for consistency"
  - "Used Freezed for type-safe immutable models"
  - "Implemented optimistic updates in provider for instant UI feedback"
  - "Made digest the default authenticated route"
  - "Used LinearProgressIndicator in app bar instead of custom widget for simplicity"

patterns-established:
  - "Digest feature follows same architecture as Feed feature"
  - "AsyncNotifier with AsyncValue for loading/error/data states"
  - "Card opacity 0.6 when processed for visual feedback"
  - "Rank badge (1-5) as circular overlay on cards"
  - "Reason badge below thumbnail for selection explanation"

# Metrics
duration: 0min
completed: 2026-02-03
---

# Phase 02 Plan 01: Digest Screen UI Summary

**Flutter digest screen with 5 article cards, progress indicator, Riverpod state management, and Freezed models matching the API schema.**

## Performance

- **Duration:** 0 min (files already implemented)
- **Started:** 2026-02-03
- **Completed:** 2026-02-03
- **Tasks:** 7/7 complete
- **Files modified:** 7

## Accomplishments

### 1. Freezed Models (digest_models.dart)

Created type-safe immutable models matching the API schema:

- **SourceMini**: Minimal source representation (id, name, logoUrl, theme)
- **DigestItem**: Single article in digest with content metadata, source info, rank (1-5), selection reason, and action states (isRead, isSaved, isDismissed)
- **DigestResponse**: Complete digest with 5 items, completion status, and timestamps
- **DigestCompletionResponse**: Completion tracking with closure streak info

Uses `@freezed` with JSON serialization via `fromJson`/`toJson` methods.

### 2. Digest Repository (digest_repository.dart)

Repository for `/api/digest` API calls with:

- **getDigest({DateTime? date})**: GET /api/digest with optional date parameter
- **getDigestById(String digestId)**: GET /api/digest/{id}
- **applyAction()**: POST /api/digest/{id}/action for read/save/not_interested/undo
- **completeDigest()**: POST /api/digest/{id}/complete
- **generateDigest()**: POST /api/digest/generate for on-demand generation

Custom exceptions for 404 (DigestNotFoundException) and 503 (DigestGenerationException).

### 3. Riverpod Provider (digest_provider.dart)

State management with AsyncNotifier:

- **State**: `AsyncValue<DigestResponse?>` for loading/error/data handling
- **loadDigest()**: Load digest on initialization
- **refreshDigest()**: Pull-to-refresh functionality
- **applyAction()**: Optimistic updates with rollback on error
- **completeDigest()**: Mark digest as finished with haptic feedback
- **Computed properties**: `processedCount`, `progress` (0.0-1.0)
- **Auto-complete**: Automatically calls completeDigest when all items processed

### 4. Progress Bar Widget (progress_bar.dart)

Reusable progress indicator:

- **Parameters**: `processedCount`, `totalCount` (default 5)
- **Visual**: 5 segments with animated fill using AnimatedContainer
- **Animation**: 300ms easeInOut curve
- **Text**: Shows "X/5" on right side
- **Colors**: Primary for filled, backgroundSecondary for unfilled

### 5. Digest Card Widget (digest_card.dart)

Article card adapted from FeedCard:

- **FacteurCard wrapper** with padding and border radius
- **Thumbnail**: 16:9 aspect ratio with CachedNetworkImage
- **Rank badge**: Circular overlay showing 1-5 (top-left)
- **Reason badge**: Selection explanation below thumbnail
- **Title**: displaySmall style, 20px, maxLines: 2
- **Source row**: Logo (16x16) + name + recency
- **Type icon**: Video/audio indicators
- **Processed badge**: "Lu" or "Masqué" when actioned (top-right)
- **Opacity**: 0.6 when processed for visual feedback
- **Footer**: backgroundSecondary with top border

### 6. Digest Screen (digest_screen.dart)

Main screen for "Votre Essentiel":

- **App bar**: "Votre Essentiel" title with Fraunces font, StreakIndicator, progress bar
- **Body**: ListView with 5 DigestCard items
- **States**: Loading (spinner), Error (retry button), Data (cards), Empty (message)
- **Pull-to-refresh**: RefreshIndicator with digest refresh
- **Navigation**: Tap card opens content detail, completion navigates to closure screen
- **First-time welcome**: DigestWelcomeModal shown on first visit

### 7. Route Configuration (routes.dart)

Navigation updates:

- **RouteNames.digest**: 'digest'
- **RoutePaths.digest**: '/digest'
- **ShellRoute**: Added digest route as first tab (Essentiel)
- **Default route**: Authenticated users redirected to digest instead of feed
- **Onboarding completion**: Redirects to digest with ?first=true param

## Task Commits

All files were already implemented. No new commits needed for this execution.

## Files Created/Modified

### Created
- `apps/mobile/lib/features/digest/models/digest_models.dart` - Freezed models for API
- `apps/mobile/lib/features/digest/models/digest_models.freezed.dart` - Generated freezed code
- `apps/mobile/lib/features/digest/models/digest_models.g.dart` - Generated JSON serialization
- `apps/mobile/lib/features/digest/repositories/digest_repository.dart` - API client
- `apps/mobile/lib/features/digest/providers/digest_provider.dart` - Riverpod state management
- `apps/mobile/lib/features/digest/widgets/progress_bar.dart` - Progress indicator widget
- `apps/mobile/lib/features/digest/widgets/digest_card.dart` - Article card widget
- `apps/mobile/lib/features/digest/screens/digest_screen.dart` - Main digest screen

### Modified
- `apps/mobile/lib/config/routes.dart` - Added digest route and made it default

## Decisions Made

None - files executed exactly as planned. Key patterns observed:

1. **Visual consistency**: DigestCard reuses FeedCard patterns exactly (FacteurCard, thumbnail aspect ratio, title styling, source row)
2. **State management**: Riverpod AsyncNotifier with optimistic updates for instant feedback
3. **Progress indication**: LinearProgressIndicator in app bar + ProgressBar widget for X/5 display
4. **Default route**: Digest becomes primary destination after authentication/onboarding

## Deviations from Plan

None - plan executed exactly as written.

All files exist and match specifications:
- Models have all API fields with proper types ✓
- Repository follows feed_repository patterns ✓
- Provider uses AsyncValue.guard pattern ✓
- ProgressBar has 5 animated segments ✓
- DigestCard has rank badge and reason display ✓
- DigestScreen loads data and shows 5 cards ✓
- Route registered at /digest ✓

## Issues Encountered

None

## Verification Results

- ✅ `flutter analyze` - 0 errors in digest files
- ✅ Models compile with Freezed generation
- ✅ Provider architecture matches feed provider patterns
- ✅ Visual design matches FeedCard exactly
- ✅ Route accessible at /digest

## Next Phase Readiness

### Ready for 02-02 (Article Actions)

Digest screen foundation complete:
- Cards display with rank badges
- Provider has applyAction method stubbed
- onAction callback ready for ArticleActionBar integration

### Ready for 02-03 (Closure Screen)

Completion flow prepared:
- Provider has completeDigest method
- Auto-completion when all items processed
- Navigation to closure screen on completion

---
*Phase: 02-frontend*
*Completed: 2026-02-03*
