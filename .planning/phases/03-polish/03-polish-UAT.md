---
status: complete
phase: 03-polish
source: 03-01-SUMMARY.md, 03-02-SUMMARY.md, 03-03-SUMMARY.md, 03-04-SUMMARY.md, 03-05-SUMMARY.md
started: 2026-02-09T00:00:00Z
updated: 2026-02-09T00:25:00Z
---

## Current Test

[testing complete]

## Pre-existing Issues (not Phase 3 regressions)

### A. Digest card title overflow
reported: "Le titre est parfois trop long et engendre un bug d'affichage critique — sortie du container"
file: apps/mobile/lib/features/digest/widgets/digest_briefing_section.dart (line 210)
root_cause: item.reason.toUpperCase() in Row without overflow handling
severity: major

### B. Masquer notification lacks context
reported: "Après clic sur Masquer [Thème] ou [Source], préciser dans la notification que les changements seront pris en compte pour les prochains Essentiels du Jour"
file: apps/mobile/lib/features/digest/widgets/digest_personalization_sheet.dart (lines 190, 209)
root_cause: Messages too brief — don't mention effect timing
severity: minor

## Tests

### 1. Push notification permission request on first launch
expected: On first app launch, the app requests notification permission via system dialog.
result: skipped
reason: flutter_local_notifications does not support web/Chrome. Requires native Android/iOS build.

### 2. Push notification scheduled at 8am
expected: A daily local notification scheduled at 8:00 AM Europe/Paris with text "Ton essentiel du jour est prêt".
result: skipped
reason: flutter_local_notifications does not support web/Chrome. Requires native build.

### 3. Notification tap opens Digest screen
expected: Tapping the push notification navigates directly to the Digest screen.
result: skipped
reason: flutter_local_notifications does not support web/Chrome. Requires native build.

### 4. Settings push notification toggle
expected: In Settings, the push notification toggle works. Turning it OFF cancels the notification. Turning it ON re-schedules it.
result: issue
reported: "In Notification settings, I can't change the switch to activate them"
severity: major

### 5. Digest article actions tracked as analytics events
expected: When you read, save, or dismiss an article in the digest, a content_interaction analytics event is fired with surface='digest'.
result: skipped
reason: Production Railway runs main branch. Cannot verify end-to-end until Phase 3 is deployed. Code review confirms wiring is correct.

### 6. Digest closure session event
expected: When you complete the digest (closure screen), a digest_session event fires once with breakdown stats.
result: skipped
reason: Production Railway runs main branch. Cannot verify end-to-end until Phase 3 is deployed. Code review confirms wiring is correct.

### 7. GET /analytics/digest-metrics endpoint
expected: GET /api/analytics/digest-metrics returns JSON with completion_rate, avg_closure_time_seconds, total_closures, interaction breakdown.
result: skipped
reason: Endpoint exists on Phase 3 branch but production Railway runs main. Cannot test against prod.

### 8. Digest unit tests pass
expected: Running pytest on test_digest_selector.py and test_digest_service.py passes all 24 tests.
result: pass
note: 24/24 passed in 1.49s (PYTHONPATH=. pytest tests/test_digest_selector.py tests/test_digest_service.py -v)

### 9. Digest loads without delay (batch queries)
expected: Opening the digest screen loads articles quickly, sub-second on normal connection.
result: pass

### 10. Digest caching on re-navigation
expected: Navigate away from digest and back — digest appears instantly without new API call.
result: pass

## Summary

total: 10
passed: 3
issues: 1
pending: 0
skipped: 6

## Gaps

- truth: "Settings push notification toggle enables/disables daily notification"
  status: failed
  reason: "User reported: In Notification settings, I can't change the switch to activate them"
  severity: major
  test: 4
  root_cause: "notifications_screen.dart _buildToggleTile passes onChanged parameter but Switch.adaptive has onChanged: null (hardcoded disabled). Entire tile at Opacity 0.5 with 'Arrive bientôt !' badge. Plan 03-01 wired the provider but never updated the screen to enable the switch."
  artifacts:
    - path: "apps/mobile/lib/features/settings/screens/notifications_screen.dart"
      issue: "Switch.adaptive onChanged: null (line 161), Opacity 0.5 (line 107-108), placeholder text 'pas encore actives' (line 83-84), 'Arrive bientôt !' badge (line 139)"
  missing:
    - "Pass the onChanged callback to Switch.adaptive instead of null"
    - "Remove Opacity 0.5 wrapper from _buildToggleTile"
    - "Remove 'Arrive bientôt !' badge"
    - "Update help text to explain notification behavior instead of 'sera disponible prochainement'"
