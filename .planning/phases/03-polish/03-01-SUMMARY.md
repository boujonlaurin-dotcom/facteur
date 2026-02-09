---
phase: 03-polish
plan: 01
subsystem: ui
tags: [flutter_local_notifications, timezone, push-notifications, local-notifications, riverpod]

# Dependency graph
requires:
  - phase: 01-production-fixes
    provides: Digest generation scheduler at 8am Europe/Paris
provides:
  - Local push notification service (PushNotificationService)
  - Daily 8am Europe/Paris digest notification
  - Settings opt-out integration for push notifications
  - Notification tap navigates to DigestScreen
affects: [03-05-performance]

# Tech tracking
tech-stack:
  added: [flutter_local_notifications ^20.0.0, timezone ^0.10.0, flutter_timezone ^3.0.1]
  patterns: [singleton service with factory constructor, v20 named parameter API, Hive-based feature toggle with side-effects]

key-files:
  created:
    - apps/mobile/lib/core/services/push_notification_service.dart
    - apps/mobile/lib/core/providers/push_notification_provider.dart
    - apps/mobile/lib/core/providers/push_notification_provider.g.dart
  modified:
    - apps/mobile/pubspec.yaml
    - apps/mobile/lib/main.dart
    - apps/mobile/lib/features/settings/providers/notifications_settings_provider.dart
    - apps/mobile/android/app/build.gradle.kts
    - apps/mobile/android/app/src/main/AndroidManifest.xml
    - apps/mobile/ios/Runner/AppDelegate.swift

key-decisions:
  - "Named class PushNotificationService to avoid collision with existing NotificationService (SnackBar UI)"
  - "Used timezone ^0.10.0 (not ^0.9.4 from plan) because flutter_local_notifications v20 requires ^0.10.0"
  - "Singleton factory pattern for PushNotificationService matches usage across main.dart and settings provider"

patterns-established:
  - "Push notification service: singleton with factory, static navigatorKey setter, init guard"
  - "Settings toggle side-effects: Hive persistence + service call in same method"

# Metrics
duration: 14min
completed: 2026-02-08
---

# Phase 3 Plan 01: Local Push Notification Summary

**Daily 8am local push notification using flutter_local_notifications v20 with Europe/Paris timezone, Settings opt-out toggle, and tap-to-digest navigation**

## Performance

- **Duration:** 14 min
- **Started:** 2026-02-08T00:11:04Z
- **Completed:** 2026-02-08T00:25:12Z
- **Tasks:** 2
- **Files modified:** 11

## Accomplishments
- PushNotificationService with full v20 named parameter API (init, schedule, cancel, requestPermission)
- Daily notification at 8am Europe/Paris using `DateTimeComponents.time` repeat
- App startup initializes service, requests permission, schedules if enabled
- Settings push toggle wired to schedule/cancel notification
- Notification tap navigates to `/digest` via GoRouter's navigatorKey
- Android desugaring enabled, permissions added, iOS delegate configured

## Task Commits

Each task was committed atomically:

1. **Task 1: Add flutter_local_notifications v20 and create PushNotificationService** - `6772b53` (feat)
2. **Task 2: Integrate notifications into app lifecycle and settings toggle** - `65b5331` (feat)

## Files Created/Modified
- `apps/mobile/lib/core/services/push_notification_service.dart` - PushNotificationService with init, schedule, cancel, requestPermission, tap handler (164 lines)
- `apps/mobile/lib/core/providers/push_notification_provider.dart` - Riverpod keepAlive provider for PushNotificationService
- `apps/mobile/lib/core/providers/push_notification_provider.g.dart` - Generated provider code
- `apps/mobile/pubspec.yaml` - Added flutter_local_notifications, timezone, flutter_timezone
- `apps/mobile/lib/main.dart` - PushNotificationService init, permission request, schedule on startup
- `apps/mobile/lib/features/settings/providers/notifications_settings_provider.dart` - Wired toggle to schedule/cancel
- `apps/mobile/android/app/build.gradle.kts` - Enabled core library desugaring for v20
- `apps/mobile/android/app/src/main/AndroidManifest.xml` - Added POST_NOTIFICATIONS, SCHEDULE_EXACT_ALARM, RECEIVE_BOOT_COMPLETED permissions
- `apps/mobile/ios/Runner/AppDelegate.swift` - Set UNUserNotificationCenter delegate for tap callbacks

## Decisions Made
- **Named PushNotificationService (not NotificationService):** Existing `NotificationService` at `core/ui/` handles SnackBar UI notifications and provides the `navigatorKey` used by GoRouter. Naming the new service `PushNotificationService` avoids confusion and collision.
- **Used timezone ^0.10.0 instead of plan's ^0.9.4:** flutter_local_notifications v20 requires timezone ^0.10.0. The plan specified ^0.9.4 but dependency resolution failed. Fixed to ^0.10.0 (Rule 3 - Blocking).
- **Singleton factory pattern:** Service is singleton (`PushNotificationService._()` + `factory`) since it's used in both `main.dart` and `notifications_settings_provider.dart` and should share the same plugin instance.
- **Hive check before scheduling on startup:** Instead of always scheduling, main.dart reads the Hive setting box to respect user's opt-out before scheduling.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] timezone version constraint mismatch**
- **Found during:** Task 1 (flutter pub get)
- **Issue:** Plan specified `timezone: ^0.9.4` but flutter_local_notifications v20.0.0 requires `timezone: ^0.10.0`
- **Fix:** Changed to `timezone: ^0.10.0` in pubspec.yaml
- **Files modified:** `apps/mobile/pubspec.yaml`
- **Verification:** `flutter pub get` succeeds
- **Committed in:** 6772b53

**2. [Rule 2 - Missing Critical] Android desugaring not in plan**
- **Found during:** Task 1 (reading flutter_local_notifications v20 requirements)
- **Issue:** flutter_local_notifications v20 requires core library desugaring enabled (java.time API). Plan didn't mention this Android build config requirement.
- **Fix:** Added `isCoreLibraryDesugaringEnabled = true` and `coreLibraryDesugaring` dependency to build.gradle.kts
- **Files modified:** `apps/mobile/android/app/build.gradle.kts`
- **Verification:** Flutter analyze passes, no build issues
- **Committed in:** 6772b53

**3. [Rule 2 - Missing Critical] Android notification permissions not in plan**
- **Found during:** Task 1 (platform configuration)
- **Issue:** Android requires POST_NOTIFICATIONS (API 33+), SCHEDULE_EXACT_ALARM, and RECEIVE_BOOT_COMPLETED permissions for scheduled notifications
- **Fix:** Added permissions to AndroidManifest.xml
- **Files modified:** `apps/mobile/android/app/src/main/AndroidManifest.xml`
- **Verification:** Flutter analyze passes
- **Committed in:** 6772b53

**4. [Rule 2 - Missing Critical] iOS notification delegate not in plan**
- **Found during:** Task 1 (platform configuration per research Pitfall 6)
- **Issue:** iOS requires `UNUserNotificationCenter.current().delegate = self` in AppDelegate for notification tap callbacks to fire
- **Fix:** Added delegate assignment in AppDelegate.swift
- **Files modified:** `apps/mobile/ios/Runner/AppDelegate.swift`
- **Verification:** Flutter analyze passes
- **Committed in:** 6772b53

**5. [Rule 1 - Bug] Plan specified class name "NotificationService" which already exists**
- **Found during:** Task 1 (analyzing codebase)
- **Issue:** `NotificationService` already exists at `core/ui/notification_service.dart` for SnackBar UI. Creating another with the same name would cause ambiguity and import issues.
- **Fix:** Named the new class `PushNotificationService` at `core/services/push_notification_service.dart`
- **Files modified:** All new notification files
- **Verification:** No import conflicts, both services coexist cleanly
- **Committed in:** 6772b53

---

**Total deviations:** 5 auto-fixed (2 missing critical, 1 blocking, 1 bug, 1 missing critical)
**Impact on plan:** All auto-fixes necessary for correctness and platform compatibility. No scope creep. The renamed class is semantically clearer.

## Issues Encountered
None — plan executed smoothly after addressing platform-specific requirements.

## User Setup Required
None — no external service configuration required. Local notifications are self-contained.

## Next Phase Readiness
- Push notification infrastructure complete, ready for Phase 3 Plan 02 (analytics) and beyond
- Settings toggle is wired and functional
- No blockers for subsequent plans

---
*Phase: 03-polish*
*Completed: 2026-02-08*
