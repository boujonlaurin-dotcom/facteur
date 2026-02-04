---
status: complete
phase: 02-frontend
source:
  - .planning/phases/02-frontend/02-01-PLAN.md
  - .planning/phases/02-frontend/02-02-SUMMARY.md
  - .planning/phases/02-frontend/02-03-SUMMARY.md
  - .planning/phases/02-frontend/02-04-SUMMARY.md
started: 2026-02-01T23:15:00Z
updated: 2026-02-04T12:15:00Z
---

## Current Test

[testing complete - fix plans created]

Diagnosis complete. 2 issues identified with fix plans ready for execution:
- Plan 02-09: Fix eager loading in digest_service.py
- Plan 02-10: Add greenlet>=3.0.0 dependency

## Tests

### 1. Digest Screen - 5 Articles with Progress Bar
expected: |
  When you open the app (after login), you should see:
  1. Screen titled "Votre Essentiel" 
  2. Progress bar at top showing "X/5" (e.g., "0/5")
  3. Exactly 5 article cards in a scrollable list
  4. Each card shows: article thumbnail, title, source name/logo, and a selection reason badge
  5. Cards have rank numbers (1-5) visible
result: issue
reported: "Application crashes with MissingGreenlet error and DioException 500 when loading digest"
severity: blocker
note: |
  Backend async/sync mismatch in SQLAlchemy.
  Error: sqlalchemy.exc.MissingGreenlet - greenlet_spawn has not been called.

### 2. Article Action Buttons
expected: |
  Each article card has 3 action buttons at the bottom:
  1. "Lu" (Read) button - marks article as consumed
  2. "Sauvegarder" (Save) button - bookmarks the article  
  3. "Pas intéressé" (Not Interested) button - removes article and can mute source
result: pending

### 3. Read Action and Visual Feedback
expected: |
  When you tap "Lu" on an article:
  1. The card immediately dims (opacity reduces to ~60%)
  2. A "Lu" badge appears on the card
  3. The progress bar updates (e.g., from "0/5" to "1/5")
  4. You feel a medium haptic vibration
  5. A toast/notification confirms "Article marqué comme lu"
result: pending

### 4. Save Action
expected: |
  When you tap "Sauvegarder" on an article:
  1. The button changes to active state (highlighted color)
  2. You feel a light haptic vibration
  3. A toast/notification confirms the article was saved
  4. The card does NOT dim (it's still available to read)
result: pending

### 5. Not Interested Confirmation Sheet
expected: |
  When you tap "Pas intéressé" on an article:
  1. A bottom sheet slides up with confirmation
  2. Sheet explains: "Cela masquera cet article et réduira les contenus similaires de cette source"
  3. Has two buttons: "Confirmer" and "Annuler"
  4. Does NOT immediately dismiss the article without confirmation
result: pending

### 6. Not Interested Action
expected: |
  After confirming "Pas intéressé":
  1. The card dims (similar to "Lu")
  2. A "Masqué" badge appears on the card
  3. The progress bar updates
  4. You feel a light haptic vibration
  5. Future articles from this source should appear less frequently
result: pending

### 7. Closure Screen - Completion Celebration
expected: |
  After you process all 5 articles (any combination of Read/Not Interested):
  1. A celebration screen appears automatically
  2. Screen shows "Tu es informé(e) !" headline with animation
  3. Streak celebration displays with flame icon and count (e.g., "3 jours")
  4. Digest summary shows your stats (how many read, saved, dismissed)
  5. "Explorer plus" button visible to go to the full feed
result: pending

### 8. Closure Screen Navigation
expected: |
  On the closure screen:
  1. "Explorer plus" button navigates to the Explorer/Feed tab
  2. "Fermer" button dismisses the screen and returns you to Essentiel
  3. Screen auto-dismisses after ~5 seconds if you do nothing
  4. Once dismissed/completed, you're back at digest with fresh 5 articles for next day
result: pending

### 9. Navigation Structure - 3 Tabs
expected: |
  Bottom navigation has exactly 3 tabs:
  1. "Essentiel" (primary tab) - shows your daily digest with article icon
  2. "Explorer" (secondary tab) - shows full feed with compass icon  
  3. "Paramètres" (settings tab) - app settings
  Tapping each tab switches the content correctly
result: pending

### 10. Default Route - Digest First
expected: |
  When you open the app (or complete onboarding):
  1. You land directly on "Votre Essentiel" (digest) screen
  2. NOT on the full feed anymore
  3. Digest is now the primary destination for returning users
result: pending

### 11. First-Time Welcome Modal
expected: |
  For first-time users (or after fresh install/login):
  1. A welcome modal appears over the digest screen
  2. Modal explains the digest concept
  3. Has a button to dismiss/start
  4. Modal only shows once (not on subsequent app opens)
result: pending

### 12. Article Detail Navigation
expected: |
  When you tap on an article card (not the action buttons):
  1. Opens the full article/content detail screen
  2. Shows the full article content
  3. Can navigate back to the digest
result: pending

## Summary

total: 12
passed: 0
issues: 2
pending: 11
skipped: 0

## Gaps (Backend Timeout - RESOLVED)

- truth: "Digest screen loads and displays 5 articles with progress bar"
  status: fixed
  reason: "Backend digest generation timeout resolved"
  severity: blocker
  test: 1
  root_cause: "Digest generation on backend was hanging indefinitely (>30s) due to missing database indexes and no timeout protection."
  fix_applied: |
    1. Added database indexes for digest queries (ix_contents_source_published, ix_contents_curated_published, ix_user_content_status_exclusion, ix_sources_theme)
    2. Added 8-second timeout protection to digest selector with emergency fallback
    3. Reduced candidate pool from 200 to 50 articles for faster selection
    4. Added circuit breaker pattern to API endpoint for resilience
  artifacts:
    - path: "packages/api/app/services/digest_service.py"
      change: "Added asyncio.wait_for timeout protection and circuit breaker"
    - path: "packages/api/app/services/digest_selector.py"
      change: "Optimized query performance, added timeout handling"
    - path: "packages/api/app/routers/digest.py"
      change: "Added circuit breaker with 503 fail-fast response"
  resolved_date: "2026-02-04"
  debug_session: ".planning/debug/resolved/digest-timeout-investigation.md"

  - truth: "Digest screen loads and displays 5 articles with progress bar"
    status: fix_planned
    reason: "User reported: Application crashes with MissingGreenlet error and DioException 500 when loading digest"
    severity: blocker
    test: 1
    root_cause: |
      TWO ISSUES IDENTIFIED:
      1. CODE: digest_service.py line 386-408 uses session.get() without eager loading, then accesses content.source which triggers lazy loading in async context
      2. DEPENDENCY: Missing greenlet>=3.0.0 in requirements.txt - required by SQLAlchemy for async context switching
    artifacts:
      - path: "packages/api/app/services/digest_service.py"
        issue: "Line 386: content = await self.session.get(Content, content_id) - no eager loading. Line 408: source=content.source - triggers lazy load"
        line: "386, 408"
      - path: "packages/api/app/services/digest_selector.py"
        issue: "Uses selectinload() correctly in _get_emergency_candidates() - this is the pattern to follow"
      - path: "packages/api/requirements.txt"
        issue: "Missing greenlet>=3.0.0 dependency"
    missing:
      - "Add selectinload(Content.source) to digest query in _build_digest_response()"
      - "Add 'from sqlalchemy.orm import selectinload' import"
      - "Add greenlet>=3.0.0 to requirements.txt and pyproject.toml"
    fix_plans:
      - ".planning/phases/02-frontend/02-09-PLAN.md"
      - ".planning/phases/02-frontend/02-10-PLAN.md"
    debug_sessions:
      - ".planning/debug/sqlalchemy-missing-greenlet.md"
      - ".planning/debug/async-db-session-investigation.md"

## Gaps

- truth: "Digest screen loads and displays 5 articles with progress bar"
  status: fixed
  reason: "User reported: Application crashes and closes right after the login"
  severity: blocker
  test: 1
  root_cause: "Multiple issues: (1) JSON field name mismatch (2) Null assertion in facteurColors extension (3) Unprotected async lifecycle method"
  artifacts:
    - path: "apps/mobile/lib/features/digest/models/digest_models.dart"
      issue: "21 fields missing @JsonKey annotation for snake_case API fields"
    - path: "apps/mobile/lib/config/theme.dart"
      issue: "facteurColors extension used null assertion operator (!) without fallback"
    - path: "apps/mobile/lib/features/digest/screens/digest_screen.dart"
      issue: "_checkFirstTimeWelcome() had no error handling for GoRouterState or SharedPreferences"
  fix_applied: |
    1. Added @JsonKey annotations to all snake_case fields
    2. Added null-safety fallback to facteurColors extension
    3. Added try-catch error handling to _checkFirstTimeWelcome()
    4. Added debug logging to DigestScreen.build()
  files_changed:
    - "apps/mobile/lib/features/digest/models/digest_models.dart"
    - "apps/mobile/lib/features/digest/models/digest_models.g.dart"
    - "apps/mobile/lib/config/theme.dart"
    - "apps/mobile/lib/features/digest/screens/digest_screen.dart"
  debug_sessions:
    - ".planning/debug/resolved/new-crash-after-login.md"
    - ".planning/debug/resolved/crash-after-digest-navigation.md"
