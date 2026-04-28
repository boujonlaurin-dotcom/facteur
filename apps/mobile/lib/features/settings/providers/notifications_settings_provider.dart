import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/api/notification_preferences_api_service.dart';
import '../../../core/api/providers.dart';
import '../../../core/services/push_notification_service.dart';

/// État des préférences de notifications
@immutable
class NotificationsSettings {
  final bool pushEnabled;
  final NotifPreset preset;
  final NotifTimeSlot timeSlot;
  final bool modalSeen;
  final int refusalCount;
  final DateTime? lastRefusalAt;
  final DateTime? lastRenudgeAt;
  final int renudgeShownCount;
  final bool emailDigestEnabled;

  const NotificationsSettings({
    this.pushEnabled = false,
    this.preset = NotifPreset.minimaliste,
    this.timeSlot = NotifTimeSlot.morning,
    this.modalSeen = false,
    this.refusalCount = 0,
    this.lastRefusalAt,
    this.lastRenudgeAt,
    this.renudgeShownCount = 0,
    this.emailDigestEnabled = false,
  });

  NotificationsSettings copyWith({
    bool? pushEnabled,
    NotifPreset? preset,
    NotifTimeSlot? timeSlot,
    bool? modalSeen,
    int? refusalCount,
    DateTime? lastRefusalAt,
    DateTime? lastRenudgeAt,
    int? renudgeShownCount,
    bool? emailDigestEnabled,
  }) {
    return NotificationsSettings(
      pushEnabled: pushEnabled ?? this.pushEnabled,
      preset: preset ?? this.preset,
      timeSlot: timeSlot ?? this.timeSlot,
      modalSeen: modalSeen ?? this.modalSeen,
      refusalCount: refusalCount ?? this.refusalCount,
      lastRefusalAt: lastRefusalAt ?? this.lastRefusalAt,
      lastRenudgeAt: lastRenudgeAt ?? this.lastRenudgeAt,
      renudgeShownCount: renudgeShownCount ?? this.renudgeShownCount,
      emailDigestEnabled: emailDigestEnabled ?? this.emailDigestEnabled,
    );
  }
}

/// Notifier pour les préférences de notifications.
/// Hive = cache offline ; backend = source of truth (sync au boot + après chaque mutation).
class NotificationsSettingsNotifier
    extends StateNotifier<NotificationsSettings> {
  NotificationsSettingsNotifier(this._ref)
      : super(const NotificationsSettings()) {
    _loadFromHive();
    unawaited(_syncFromBackend());
  }

  final Ref _ref;

  static const _boxName = 'settings';
  static const _kPush = 'push_notifications_enabled';
  static const _kPreset = 'notif_preset';
  static const _kTimeSlot = 'notif_time_slot';
  static const _kModalSeen = 'notif_modal_seen';
  static const _kRefusalCount = 'notif_refusal_count';
  static const _kLastRefusalAt = 'notif_last_refusal_at';
  static const _kLastRenudgeAt = 'notif_last_renudge_at';
  static const _kRenudgeShownCount = 'notif_renudge_shown_count';
  static const _kEmailDigest = 'email_digest_enabled';
  static const _kPendingSync = 'notif_prefs_pending_sync';

  Future<Box<dynamic>> _box() => Hive.openBox<dynamic>(_boxName);

  Future<void> _loadFromHive() async {
    final box = await _box();
    state = NotificationsSettings(
      pushEnabled: box.get(_kPush, defaultValue: false) as bool,
      preset: NotifPresetX.fromWire(box.get(_kPreset) as String?),
      timeSlot: NotifTimeSlotX.fromWire(box.get(_kTimeSlot) as String?),
      modalSeen: box.get(_kModalSeen, defaultValue: false) as bool,
      refusalCount: box.get(_kRefusalCount, defaultValue: 0) as int,
      lastRefusalAt: _readDate(box, _kLastRefusalAt),
      lastRenudgeAt: _readDate(box, _kLastRenudgeAt),
      renudgeShownCount:
          box.get(_kRenudgeShownCount, defaultValue: 0) as int,
      emailDigestEnabled: box.get(_kEmailDigest, defaultValue: false) as bool,
    );
  }

  DateTime? _readDate(Box<dynamic> box, String key) {
    final raw = box.get(key) as String?;
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> _persist(NotificationsSettings s) async {
    final box = await _box();
    await box.putAll({
      _kPush: s.pushEnabled,
      _kPreset: s.preset.wire,
      _kTimeSlot: s.timeSlot.wire,
      _kModalSeen: s.modalSeen,
      _kRefusalCount: s.refusalCount,
      _kLastRefusalAt: s.lastRefusalAt?.toUtc().toIso8601String(),
      _kLastRenudgeAt: s.lastRenudgeAt?.toUtc().toIso8601String(),
      _kRenudgeShownCount: s.renudgeShownCount,
      _kEmailDigest: s.emailDigestEnabled,
    });
  }

  Future<void> _syncFromBackend() async {
    try {
      final api = _ref.read(notificationPreferencesApiServiceProvider);
      final dto = await api.get();
      if (dto == null) return;

      final fresh = state.copyWith(
        pushEnabled: dto.pushEnabled,
        preset: dto.preset,
        timeSlot: dto.timeSlot,
        modalSeen: dto.modalSeen,
        refusalCount: dto.refusalCount,
        lastRefusalAt: dto.lastRefusalAt,
        lastRenudgeAt: dto.lastRenudgeAt,
        renudgeShownCount: dto.renudgeShownCount,
      );
      state = fresh;
      await _persist(fresh);
      await _drainPendingSync();
    } catch (e) {
      debugPrint('NotifSettings: backend sync failed: $e');
    }
  }

  /// Re-pousse le dernier état si une mutation précédente a échoué offline.
  Future<void> _drainPendingSync() async {
    final box = await _box();
    final pending = box.get(_kPendingSync, defaultValue: false) as bool;
    if (!pending) return;
    await _patchBackend(state);
    await box.put(_kPendingSync, false);
  }

  Future<void> _patchBackend(NotificationsSettings s) async {
    try {
      final api = _ref.read(notificationPreferencesApiServiceProvider);
      final result = await api.patch(
        pushEnabled: s.pushEnabled,
        preset: s.preset,
        timeSlot: s.timeSlot,
        modalSeen: s.modalSeen,
        refusalCount: s.refusalCount,
        lastRefusalAt: s.lastRefusalAt,
        lastRenudgeAt: s.lastRenudgeAt,
        renudgeShownCount: s.renudgeShownCount,
      );
      if (result == null) {
        final box = await _box();
        await box.put(_kPendingSync, true);
      }
    } catch (e) {
      debugPrint('NotifSettings: backend patch failed: $e');
      final box = await _box();
      await box.put(_kPendingSync, true);
    }
  }

  Future<void> _reschedule() async {
    final push = PushNotificationService();
    await push.cancelDigestNotification();
    await push.cancelWeeklyCommunityPick();
    if (!state.pushEnabled) return;
    await push.scheduleDailyDigestNotification(timeSlot: state.timeSlot);
    if (state.preset == NotifPreset.curieux) {
      await push.scheduleWeeklyCommunityPick();
    }
  }

  /// Persiste, replanifie, sync backend.
  Future<void> _commit(NotificationsSettings next) async {
    state = next;
    await _persist(next);
    await _reschedule();
    unawaited(_patchBackend(next));
  }

  Future<void> setPushEnabled(bool value) async {
    if (value) {
      final pushService = PushNotificationService();
      final granted = await pushService.requestPermission();
      if (!granted) return;
      await pushService.requestExactAlarmPermission();
    }
    await _commit(state.copyWith(pushEnabled: value));
  }

  Future<void> setPreset(NotifPreset preset) =>
      _commit(state.copyWith(preset: preset));

  Future<void> setTimeSlot(NotifTimeSlot slot) =>
      _commit(state.copyWith(timeSlot: slot));

  /// Confirme la modal d'activation (préset + heure choisis, OS prompt déjà fait).
  Future<void> confirmActivation({
    required NotifPreset preset,
    required NotifTimeSlot timeSlot,
    required bool osGranted,
  }) async {
    await _commit(state.copyWith(
      pushEnabled: osGranted,
      preset: preset,
      timeSlot: timeSlot,
      modalSeen: true,
    ));
  }

  /// L'utilisateur a refusé (via *Plus tard* ou refus OS).
  Future<void> recordRefusal() async {
    final now = DateTime.now().toUtc();
    await _commit(state.copyWith(
      pushEnabled: false,
      modalSeen: true,
      refusalCount: state.refusalCount + 1,
      lastRefusalAt: now,
    ));
  }

  /// Le re-nudge banner a été affiché (pour le cap).
  Future<void> recordRenudgeShown() async {
    final now = DateTime.now().toUtc();
    await _commit(state.copyWith(
      lastRenudgeAt: now,
      renudgeShownCount: state.renudgeShownCount + 1,
    ));
  }

  Future<void> setEmailDigestEnabled(bool value) async {
    state = state.copyWith(emailDigestEnabled: value);
    final box = await _box();
    await box.put(_kEmailDigest, value);
  }
}

/// Provider pour les préférences de notifications
final notificationsSettingsProvider =
    StateNotifierProvider<NotificationsSettingsNotifier, NotificationsSettings>(
  (ref) => NotificationsSettingsNotifier(ref),
);
