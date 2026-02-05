# Issues Documentation - Phase 02-02 Frontend

## Status: BLOCKED - Requires Investigation

### Issues Still Present (ALL 6 issues reported by user)

---

## Issue 1: Bookmark Not Increasing Daily Progression
**File**: `apps/mobile/lib/features/digest/providers/digest_provider.dart`
**Current Code** (lines 163-167):
```dart
int get processedCount {
  final digest = state.value;
  if (digest == null) return 0;
  return digest.items.where((item) => item.isRead || item.isDismissed).length;
}
```
**Problem**: Only `isRead` and `isDismissed` are counted. `isSaved` is excluded.
**Attempted Fix**: Added `isSaved` to the condition, but apparently not working.
**Root Cause Unknown**: 
- Is the provider state not updating correctly?
- Is the UI not re-rendering when progression changes?
- Is there a separate progression tracking system?

**Investigation Needed**:
1. Check if `DigestItem` has `isSaved` property
2. Check how progression is displayed in UI (which widget?)
3. Check if `applyAction('save')` actually sets `isSaved = true`
4. Check if completion check (`_checkAndHandleCompletion`) is triggered after save

---

## Issue 2: Unchecking Bookmark Crashes App
**File**: `apps/mobile/lib/features/saved/screens/saved_screen.dart`
**Current Code** (lines 83-122):
```dart
Future<void> toggleSave(Content content) async {
  final currentItems = state.value;
  if (currentItems == null) return;

  final updatedItems = List<Content>.from(currentItems);

  // Optimistic Remove (Unsave)
  updatedItems.removeWhere((c) => c.id == content.id);
  state = AsyncData(updatedItems);

  try {
    final repository = ref.read(feedRepositoryProvider);
    await repository.toggleSave(content.id, false);
    // Invalidate main feed so the item reappears there
    ref.invalidate(feedProvider);
  } catch (e) {
    await refresh(); // Revert
    rethrow;
  }
}
```
**Problem**: App crashes when unchecking bookmark in saved screen
**Attempted Fix**: Added `isSaved: true` and `onSave` callback to FeedCard in saved_screen.dart, but still crashing.
**Root Cause Unknown**:
- Is the crash in `toggleSave` method?
- Is the crash in `FeedCard` widget when state changes?
- Is there a null pointer exception?

**Investigation Needed**:
1. Get crash logs/stack trace from user
2. Check if `FeedCard` handles null `onSave` callback
3. Check if state update triggers rebuild correctly
4. Test if crash happens in other contexts (feed vs saved screen)

---

## Issue 3: "Article Marked as Read" Notification Shows Unexpectedly
**File**: `apps/mobile/lib/features/detail/screens/content_detail_screen.dart`
**Current Code** (lines 167-187):
```dart
Future<void> _markAsConsumed() async {
  setState(() => _isConsumed = true);
  final content = _content;
  if (content == null) return;

  try {
    final supabase = Supabase.instance.client;
    final apiClient = ApiClient(supabase);
    final repository = FeedRepository(apiClient);
    await repository.updateContentStatus(
      content.id,
      ContentStatus.consumed,
    );

    // Notification removed in attempted fix
    // Silent update - no notification needed as this is tracked automatically
  } catch (e) {
    debugPrint('Error marking as consumed: $e');
  }
}
```
**Problem**: Notification still appears when opening article
**Attempted Fix**: Removed the `NotificationService.showSuccess()` call, but notification still appears.
**Root Cause Unknown**:
- Is there another location showing this notification?
- Is the `markContentAsConsumed` in `feed_provider.dart` showing it?
- Is the backend triggering a notification?

**Investigation Needed**:
1. Search for all occurrences of "marqué comme lu" in codebase
2. Check `feed_provider.dart` line 211 (mentioned in grep results)
3. Check if notification comes from backend push
4. Verify the fix was actually deployed

---

## Issue 4: Closure Screen Not Always Showing After 5th Article
**File**: `apps/mobile/lib/features/digest/screens/digest_screen.dart`
**Current Code** (lines 138-150):
```dart
// Note: Auto-navigation to closure screen removed
// Users can now stay on the digest screen to re-read articles
```
**Problem**: User removed auto-navigation but now closure screen doesn't show reliably
**Attempted Fix**: Removed the auto-navigation logic entirely
**Root Cause Unknown**:
- Is completion detection not working?
- Is `_checkAndHandleCompletion` not being called?
- Is the backend not marking digest as complete?

**Investigation Needed**:
1. Check if `completeDigest()` is being called
2. Check if backend returns `isCompleted: true`
3. Check navigation logic in closure_screen.dart
4. Verify that user can manually navigate to closure screen

---

## Issue 5: Feed Shows Articles from Non-Trusted Sources
**File**: `packages/api/app/services/recommendation_service.py`
**Current Code** (lines 475-481):
```python
# Base filter: Only show content from user's followed sources
# Fallback to curated sources only if user has no followed sources
if followed_source_ids:
    # User has followed sources - only show content from these sources
    query = query.where(Source.id.in_(list(followed_source_ids)))
else:
    # User hasn't followed any sources yet - fallback to curated sources
    query = query.where(Source.is_curated == True)
```
**Problem**: User still sees articles from sources they don't follow (e.g., Le Figaro)
**Attempted Fix**: Changed logic to only show followed sources
**Root Cause Unknown**:
- Is the deployment not active?
- Are followed sources not being retrieved correctly?
- Is there caching involved?

**Investigation Needed**:
1. Check if code was actually deployed (verify Railway deployment)
2. Add logging to see what `followed_source_ids` contains
3. Test query directly in database
4. Check if user's sources are actually in `followed_source_ids`

---

## Issue 6: Success Screen Still Has Countdown
**File**: `apps/mobile/lib/features/digest/screens/closure_screen.dart`
**Current Code**:
- Lines 40-42: Timer variables removed
- Lines 165-181: `_startAutoDismissTimer()` removed
- Lines 286-295: Changed button text to remove countdown
- Line 199: Changed title to "Tu es à jour !"

**Problem**: User reports countdown still present
**Attempted Fix**: Removed all timer/countdown logic
**Root Cause Unknown**:
- Was the fix deployed?
- Is user testing on old APK?
- Is there another countdown elsewhere?

**Investigation Needed**:
1. Verify closure_screen.dart in deployed code
2. Check if user has latest version
3. Search for any remaining countdown references

---

## Feature 7: Allow Re-reading Articles After Briefing Completed
**File**: `apps/mobile/lib/features/digest/screens/digest_screen.dart`
**Current Code**: Added success banner (lines 182-227)
```dart
// Success banner when digest is completed
SliverToBoxAdapter(
  child: digestAsync.when(
    data: (digest) {
      if (digest?.isCompleted == true) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: colors.success.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.success.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(PhosphorIcons.checkCircle(PhosphorIconsStyle.fill), color: colors.success),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Essentiel terminé ! Tu peux relire les articles quand tu veux.',
                  style: TextStyle(color: colors.success, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        );
      }
      return const SizedBox.shrink();
    },
    ...
  ),
),
```
**Status**: Code added but needs verification it's working

---

## Required Tests

Based on the phase plan requirements, the following tests need to be added:

### Test Suite 1: Digest Completion Flow
**Location**: `apps/mobile/test/features/digest/digest_completion_test.dart`

```dart
// Test cases needed:
1. test('completes digest when all 5 items are read', ...)
2. test('completes digest when all 5 items are dismissed', ...)
3. test('completes digest when mix of read and dismissed', ...)
4. test('completes digest when items are saved', ...)  // NEW - for Issue 1
5. test('shows closure screen after completion', ...)
6. test('shows green banner when digest already completed', ...)  // NEW - for Issue 4/7
7. test('allows re-reading articles after completion', ...)  // NEW - for Issue 4/7
```

### Test Suite 2: Bookmark Functionality  
**Location**: `apps/mobile/test/features/digest/bookmark_test.dart`

```dart
// Test cases needed:
1. test('bookmark increases progression count', ...)  // Issue 1
2. test('unchecking bookmark does not crash', ...)   // Issue 2
3. test('bookmark shows active state', ...)
4. test('bookmark persists after refresh', ...)
5. test('bookmark in saved screen works correctly', ...)  // Issue 2
```

### Test Suite 3: Feed Source Filtering
**Location**: `apps/mobile/test/features/feed/feed_sources_test.dart`

```dart
// Test cases needed:
1. test('only shows articles from followed sources', ...)  // Issue 5
2. test('falls back to curated when no sources followed', ...)
3. test('excludes muted sources', ...)
4. test('excludes muted themes', ...)
```

### Test Suite 4: Notification Suppression
**Location**: `apps/mobile/test/features/detail/notification_test.dart`

```dart
// Test cases needed:
1. test('does not show article read notification', ...)  // Issue 3
2. test('shows save notification', ...)  // Should still show
3. test('shows not interested notification', ...)  // Should still show
```

---

## Files Modified in Attempted Fixes

1. `apps/mobile/lib/features/digest/providers/digest_provider.dart`
   - Modified `processedCount` getter to include `isSaved`
   - Modified `_checkAndHandleCompletion` to include `isSaved`

2. `apps/mobile/lib/features/saved/screens/saved_screen.dart`
   - Added `isSaved: true` to FeedCard
   - Added `onSave` callback

3. `apps/mobile/lib/features/detail/screens/content_detail_screen.dart`
   - Removed notification in `_markAsConsumed`

4. `apps/mobile/lib/features/digest/screens/closure_screen.dart`
   - Removed countdown timer
   - Changed title to "Tu es à jour !"
   - Added reassuring message

5. `apps/mobile/lib/features/digest/screens/digest_screen.dart`
   - Removed auto-navigation to closure screen
   - Added green completion banner

6. `packages/api/app/services/recommendation_service.py`
   - Changed to only show followed sources

---

## Next Steps for Next Agent

1. **Verify Deployments**: Check if all changes were actually deployed to Railway
2. **Get Crash Logs**: For Issue 2, get full stack trace from user
3. **Add Logging**: Add extensive logging to track state changes
4. **Run Tests**: Create and run the test suites above
5. **Test on Device**: Have user test with latest build
6. **Database Check**: Verify user's followed sources in database

## Priority Order

1. **HIGHEST**: Issue 2 (Crash) - App stability
2. **HIGH**: Issue 4 (Closure screen) - Core feature broken
3. **HIGH**: Issue 5 (Feed sources) - Wrong content shown
4. **MEDIUM**: Issue 1 (Bookmark progression) - UX issue
5. **MEDIUM**: Issue 3 (Notification) - UX annoyance
6. **LOW**: Issue 6 (Countdown) - Already fixed, verify deployment
7. **LOW**: Issue 7 (Re-reading) - Feature request, code added
