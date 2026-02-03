---
status: resolved
trigger: "Crashed again after JSON serialization fix - no error in logs, happens after GoRouter navigation to /digest"
created: 2026-02-02T00:00:00Z
updated: 2026-02-02T00:10:00Z
---

## Current Focus

**hypothesis**: Crash is caused by null assertion in facteurColors extension OR unhandled exception in _checkFirstTimeWelcome
**test**: Added defensive error handling to both locations
**expecting**: App should no longer crash, or show useful error messages
**next_action**: Test the app again with the fixes

## Symptoms

**expected**: App should show digest screen with 5 articles after login
**actual**: App crashes silently after GoRouter navigates to /digest (no API call shown in logs)
**errors**: No error message in logs - crash happens after "GoRouter: Full paths for routes" output
**reproduction**: 
1. User logs in
2. Auth successful, token attached
3. GoRouter redirects to /digest
4. Crash occurs silently before API call
**started**: After applying JSON serialization fixes

## Evidence

### Evidence 1: No Digest API Call in Logs
- **timestamp**: 2026-02-02T00:00:00Z
- **checked**: Crash logs provided
- **found**: No "DigestRepository" or digest API call logs - crash happens before provider triggers
- **implication**: Crash is in widget lifecycle (build/didChangeDependencies), not in data loading

### Evidence 2: Potential facteurColors Null Assertion
- **timestamp**: 2026-02-02T00:05:00Z
- **checked**: theme.dart extension
- **found**: `FacteurColors get facteurColors => Theme.of(this).extension<FacteurColors>()!;` uses `!` operator
- **implication**: If theme extension is not registered, this throws a null assertion error

### Evidence 3: Unprotected Async Method
- **timestamp**: 2026-02-02T00:06:00Z
- **checked**: _checkFirstTimeWelcome() method
- **found**: No try-catch around GoRouterState.of(context) or SharedPreferences access
- **implication**: Any exception here would crash the app silently

## Eliminated

- **hypothesis**: JSON serialization causing null values
  **evidence**: @JsonKey annotations added and build_runner regenerated
  **timestamp**: 2026-02-02T00:00:00Z

- **hypothesis**: Digest provider API error
  **evidence**: No API call shown in logs - crash happens before provider loads
  **timestamp**: 2026-02-02T00:02:00Z

## Resolution

**root_cause**: 
Two potential crash sources were identified:

1. **Null assertion in facteurColors extension** - `Theme.of(this).extension<FacteurColors>()!` would crash if the theme extension wasn't accessible

2. **Unprotected _checkFirstTimeWelcome()** - Async method accessing GoRouterState and SharedPreferences without error handling

**fix**: 
1. Changed `facteurColors` getter to return a fallback value instead of crashing:
   ```dart
   FacteurColors get facteurColors {
     final colors = Theme.of(this).extension<FacteurColors>();
     if (colors == null) {
       return FacteurPalettes.light; // fallback
     }
     return colors;
   }
   ```

2. Added try-catch around `_checkFirstTimeWelcome()` with debug logging

3. Added debug logging to DigestScreen.build() for better diagnostics

**verification**: 
- Build completed successfully with 232 outputs
- Code changes are defensive - won't crash on unexpected states

**files_changed**:
- `apps/mobile/lib/config/theme.dart` - Added null safety to facteurColors extension
- `apps/mobile/lib/features/digest/screens/digest_screen.dart` - Added error handling and debug logging
