import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// État des préférences de notifications
class NotificationsSettings {
  final bool pushEnabled;
  final bool emailDigestEnabled;

  const NotificationsSettings({
    this.pushEnabled = true,
    this.emailDigestEnabled = false,
  });

  NotificationsSettings copyWith({
    bool? pushEnabled,
    bool? emailDigestEnabled,
  }) {
    return NotificationsSettings(
      pushEnabled: pushEnabled ?? this.pushEnabled,
      emailDigestEnabled: emailDigestEnabled ?? this.emailDigestEnabled,
    );
  }
}

/// Notifier pour les préférences de notifications (persisté via Hive)
class NotificationsSettingsNotifier
    extends StateNotifier<NotificationsSettings> {
  NotificationsSettingsNotifier() : super(const NotificationsSettings()) {
    _loadFromHive();
  }

  static const String _boxName = 'settings';
  static const String _pushKey = 'push_notifications_enabled';
  static const String _emailKey = 'email_digest_enabled';

  Future<void> _loadFromHive() async {
    final box = await Hive.openBox<dynamic>(_boxName);
    state = NotificationsSettings(
      pushEnabled: box.get(_pushKey, defaultValue: true) as bool,
      emailDigestEnabled: box.get(_emailKey, defaultValue: false) as bool,
    );
  }

  Future<void> setPushEnabled(bool value) async {
    state = state.copyWith(pushEnabled: value);
    final box = await Hive.openBox<dynamic>(_boxName);
    await box.put(_pushKey, value);
  }

  Future<void> setEmailDigestEnabled(bool value) async {
    state = state.copyWith(emailDigestEnabled: value);
    final box = await Hive.openBox<dynamic>(_boxName);
    await box.put(_emailKey, value);
  }
}

/// Provider pour les préférences de notifications
final notificationsSettingsProvider =
    StateNotifierProvider<NotificationsSettingsNotifier, NotificationsSettings>(
  (ref) => NotificationsSettingsNotifier(),
);
