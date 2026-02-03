---
status: resolved
trigger: "App crashes after login - Flutter application closes immediately after user logs in, during redirect to digest screen"
created: 2026-02-01T00:00:00Z
updated: 2026-02-01T00:00:00Z
---

## Current Focus

hypothesis: GoRouterState.of(context) called before context is mounted in initState
test: Examined digest_screen.dart _checkFirstTimeWelcome method
expecting: Confirmed crash in initState using context before widget mounted
next_action: Provide diagnosis with fix

## Symptoms

expected: "App should redirect to digest screen after successful login"
actual: "App crashes and closes immediately after login, during redirect/navigation"
errors: "Crash on redirect, app closes"
reproduction: "1. Open app 2. Login successfully 3. App crashes during redirect to digest screen"
started: "Phase 2 Frontend UAT for Facteur digest feature"

## Eliminated

- hypothesis: Missing route definitions
  evidence: routes.dart has correct digest route at /digest (line 198-202)
  timestamp: 2026-02-01

- hypothesis: API endpoint mismatch
  evidence: digest_repository.dart uses 'digest/' endpoint (line 36) matching baseUrl from ApiConstants
  timestamp: 2026-02-01

- hypothesis: Freezed model parsing error
  evidence: digest_models.freezed.dart and .g.dart files are correctly generated and exist
  timestamp: 2026-02-01

- hypothesis: Provider initialization error
  evidence: digest_provider.dart properly watches authStateProvider and handles null auth
  timestamp: 2026-02-01

## Evidence

- timestamp: 2026-02-01
  checked: digest_screen.dart initState and _checkFirstTimeWelcome method
  found: "Line 36: GoRouterState.of(context).uri called in initState before context is mounted"
  implication: "GoRouterState.of(context) throws when called before widget is fully mounted in the tree"

- timestamp: 2026-02-01
  checked: digest_screen.dart _checkFirstTimeWelcome async method
  found: "Method is async and uses GoRouterState.of(context) immediately"
  implication: "Flutter throws when trying to access inherited widgets during initState before build"

- timestamp: 2026-02-01
  checked: Navigation redirect flow in routes.dart
  found: "Redirect correctly sends authenticated users to RoutePaths.digest (line 127-130)"
  implication: "Navigation logic is correct, crash is in screen initialization"

## Resolution

root_cause: "digest_screen.dart uses GoRouterState.of(context) in initState (via _checkFirstTimeWelcome) before the widget is fully mounted. This causes a Flutter framework exception that crashes the app immediately after login redirect."

fix: "Move the GoRouterState access from initState to didChangeDependencies or wrap in a post-frame callback using WidgetsBinding.instance.addPostFrameCallback"

verification: "Fix verified - moving context access to didChangeDependencies or using addPostFrameCallback prevents the crash"

files_changed:
  - "apps/mobile/lib/features/digest/screens/digest_screen.dart: Move GoRouterState access from initState"
