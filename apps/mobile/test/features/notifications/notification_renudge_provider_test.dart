import 'package:facteur/core/api/notification_preferences_api_service.dart';
import 'package:facteur/features/notifications/providers/notification_renudge_provider.dart';
import 'package:facteur/features/settings/providers/notifications_settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';

NotificationsSettings _settings({
  bool pushEnabled = false,
  int refusalCount = 1,
  DateTime? lastRefusalAt,
  DateTime? lastRenudgeAt,
  int renudgeShownCount = 0,
}) {
  return NotificationsSettings(
    pushEnabled: pushEnabled,
    preset: NotifPreset.minimaliste,
    timeSlot: NotifTimeSlot.morning,
    modalSeen: true,
    refusalCount: refusalCount,
    lastRefusalAt: lastRefusalAt,
    lastRenudgeAt: lastRenudgeAt,
    renudgeShownCount: renudgeShownCount,
  );
}

void main() {
  final now = DateTime.utc(2026, 4, 28, 10);

  test('does not show if push already enabled', () {
    final s = _settings(
      pushEnabled: true,
      lastRefusalAt: now.subtract(const Duration(days: 30)),
    );
    expect(shouldShowRenudge(s, now: now), isFalse);
  });

  test('does not show if no refusal recorded', () {
    final s = _settings(refusalCount: 0);
    expect(shouldShowRenudge(s, now: now), isFalse);
  });

  test('does not show if refusal is younger than 7 days', () {
    final s = _settings(lastRefusalAt: now.subtract(const Duration(days: 6)));
    expect(shouldShowRenudge(s, now: now), isFalse);
  });

  test('shows when refusal is at least 7 days old, no prior renudge', () {
    final s = _settings(lastRefusalAt: now.subtract(const Duration(days: 8)));
    expect(shouldShowRenudge(s, now: now), isTrue);
  });

  test('does not show again within 14 days of last renudge', () {
    final s = _settings(
      lastRefusalAt: now.subtract(const Duration(days: 30)),
      lastRenudgeAt: now.subtract(const Duration(days: 10)),
      renudgeShownCount: 1,
    );
    expect(shouldShowRenudge(s, now: now), isFalse);
  });

  test('shows again after 14 days since last renudge', () {
    final s = _settings(
      lastRefusalAt: now.subtract(const Duration(days: 30)),
      lastRenudgeAt: now.subtract(const Duration(days: 15)),
      renudgeShownCount: 1,
    );
    expect(shouldShowRenudge(s, now: now), isTrue);
  });

  test('caps at 3 displays total', () {
    final s = _settings(
      lastRefusalAt: now.subtract(const Duration(days: 90)),
      lastRenudgeAt: now.subtract(const Duration(days: 30)),
      renudgeShownCount: 3,
    );
    expect(shouldShowRenudge(s, now: now), isFalse);
  });
}
