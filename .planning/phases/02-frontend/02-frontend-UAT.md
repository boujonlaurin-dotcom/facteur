---
status: testing
phase: 02-frontend
source:
  - .planning/phases/02-frontend/02-01-PLAN.md
  - .planning/phases/02-frontend/02-02-SUMMARY.md
  - .planning/phases/02-frontend/02-03-SUMMARY.md
  - .planning/phases/02-frontend/02-04-SUMMARY.md
started: 2026-02-01T23:15:00Z
updated: 2026-02-01T23:20:00Z
---

## Current Test

number: 1
name: Digest Screen - Loading Issue (RETEST #6)
expected: |
  When you open the app (after login), you should see:
  1. Screen titled "Votre Essentiel" 
  2. Progress bar at top showing "X/5" (e.g., "0/5")
  3. Exactly 5 article cards in a scrollable list
  4. Each card shows: article thumbnail, title, source name/logo, and a selection reason badge
  5. Cards have rank numbers (1-5) visible
note: |
  Backend now running locally (confirmed).
  Timeout increased to 60s but still infinite loading.
  Need to investigate why digest request hangs.
awaiting: user response

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
reported: "Infinite loading on Essentiel feed. API timeout errors for /digest and /users/streak endpoints (30s connection timeout)"
severity: blocker
note: "Backend connectivity issue - requests timing out"

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
issues: 1
pending: 11
skipped: 0

## Gaps

- truth: "Digest screen loads and displays 5 articles with progress bar"
  status: diagnosed
  reason: "Token attaches correctly, but API request times out after 30s. Same issue on production Railway backend."
  severity: blocker
  test: 1
  root_cause: "Digest generation on backend hangs indefinitely (>30s). Likely caused by: (1) missing user sources causing fallback loop, (2) slow database queries, or (3) digest_selector algorithm blocking."
  artifacts:
    - path: "apps/mobile/lib/features/digest/repositories/digest_repository.dart"
      issue: "GET /api/digest times out after 30s"
    - path: "packages/api/app/services/digest_service.py"
      issue: "get_or_create_digest() likely hanging during generation"
    - path: "packages/api/app/services/digest_selector.py"
      issue: "select_for_user() may have infinite loop or slow query"
  missing:
    - "Verify user has sources configured (check user_sources table)"
    - "Test other endpoints (/api/feed) to confirm token works"
    - "Check Railway backend logs for errors during digest requests"
    - "Profile digest_selector performance"
  debug_session: ".planning/debug/digest-timeout-investigation.md"

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
