---
phase: 02-frontend
plan: 05
type: gap_closure
status: complete
completed: 2026-02-01T23:20:00Z
duration: 2min
---

# Phase 02 Plan 05: Fix Login Crash (Gap Closure)

**Issue:** App crashes immediately after login  
**Root Cause:** `GoRouterState.of(context)` called in `initState()` before widget mounted  
**Fix:** Moved `_checkFirstTimeWelcome()` from `initState()` to `didChangeDependencies()`

---

## Changes Made

### File: `apps/mobile/lib/features/digest/screens/digest_screen.dart`

**Before (lines 25-32):**
```dart
class _DigestScreenState extends ConsumerState<DigestScreen> {
  bool _showWelcome = false;

  @override
  void initState() {
    super.initState();
    _checkFirstTimeWelcome();  // ❌ CRASH: context not available
  }
```

**After (lines 25-44):**
```dart
class _DigestScreenState extends ConsumerState<DigestScreen> {
  bool _showWelcome = false;
  bool _hasCheckedWelcome = false;  // ✅ Flag to prevent re-execution

  @override
  void initState() {
    super.initState();
    // Note: _checkFirstTimeWelcome moved to didChangeDependencies()
    // because GoRouterState.of(context) requires mounted context
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasCheckedWelcome) {  // ✅ Only run once
      _hasCheckedWelcome = true;
      _checkFirstTimeWelcome();  // ✅ Safe: context is now available
    }
  }
```

---

## Verification

### Static Analysis
```bash
$ flutter analyze lib/features/digest/screens/digest_screen.dart
Analyzing digest_screen.dart...
1 issue found. (info level only - unawaited future, not crash related)
```

✅ No errors related to GoRouterState or lifecycle  
✅ File compiles successfully  

### What Was Fixed
- `GoRouterState.of(context)` is now called in `didChangeDependencies()` where context is valid
- Added `_hasCheckedWelcome` flag to ensure welcome check only runs once
- Welcome modal functionality preserved for first-time users

---

## Ready for Retest

**To verify the fix:**
1. Launch the app
2. Log in with test account
3. App should now load the digest screen without crashing
4. You should see "Votre Essentiel" title and progress bar

**Related:** See updated UAT.md for test checklist

---

## Technical Notes

**Flutter Lifecycle Rule:** InheritedWidgets (like GoRouterState) cannot be accessed during `initState()` because the widget's context is not yet associated with the element tree. They must be accessed in:
- `didChangeDependencies()` - called after initState when dependencies are available
- `build()` - context is always available here
- Post-frame callbacks via `WidgetsBinding.instance.addPostFrameCallback()`

**Why `didChangeDependencies()`:**
- Called immediately after `initState()`
- InheritedWidgets are established
- Safe to call `GoRouterState.of(context)`
- Flag ensures it only runs once (not on every dependency change)
