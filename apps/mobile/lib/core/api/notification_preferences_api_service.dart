import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

enum NotifPreset { minimaliste, curieux }

enum NotifTimeSlot { morning, evening }

extension NotifPresetX on NotifPreset {
  String get wire => switch (this) {
        NotifPreset.minimaliste => 'minimaliste',
        NotifPreset.curieux => 'curieux',
      };

  static NotifPreset fromWire(String? raw) =>
      raw == 'curieux' ? NotifPreset.curieux : NotifPreset.minimaliste;
}

extension NotifTimeSlotX on NotifTimeSlot {
  String get wire => switch (this) {
        NotifTimeSlot.morning => 'morning',
        NotifTimeSlot.evening => 'evening',
      };

  static NotifTimeSlot fromWire(String? raw) =>
      raw == 'evening' ? NotifTimeSlot.evening : NotifTimeSlot.morning;
}

@immutable
class NotificationPreferencesDto {
  final bool pushEnabled;
  final NotifPreset preset;
  final NotifTimeSlot timeSlot;
  final String timezone;
  final int refusalCount;
  final DateTime? lastRefusalAt;
  final DateTime? lastRenudgeAt;
  final int renudgeShownCount;
  final bool modalSeen;
  final bool notifVeilleEnabled;

  const NotificationPreferencesDto({
    required this.pushEnabled,
    required this.preset,
    required this.timeSlot,
    required this.timezone,
    required this.refusalCount,
    required this.lastRefusalAt,
    required this.lastRenudgeAt,
    required this.renudgeShownCount,
    required this.modalSeen,
    required this.notifVeilleEnabled,
  });

  factory NotificationPreferencesDto.fromJson(Map<String, dynamic> json) =>
      NotificationPreferencesDto(
        pushEnabled: json['push_enabled'] as bool? ?? false,
        preset: NotifPresetX.fromWire(json['preset'] as String?),
        timeSlot: NotifTimeSlotX.fromWire(json['time_slot'] as String?),
        timezone: json['timezone'] as String? ?? 'Europe/Paris',
        refusalCount: json['refusal_count'] as int? ?? 0,
        lastRefusalAt: _parseDate(json['last_refusal_at']),
        lastRenudgeAt: _parseDate(json['last_renudge_at']),
        renudgeShownCount: json['renudge_shown_count'] as int? ?? 0,
        modalSeen: json['modal_seen'] as bool? ?? false,
        notifVeilleEnabled: json['notif_veille_enabled'] as bool? ?? false,
      );

  static DateTime? _parseDate(dynamic v) =>
      v is String ? DateTime.tryParse(v) : null;
}

/// Service REST pour les préférences de notifications push.
class NotificationPreferencesApiService {
  final ApiClient _apiClient;

  NotificationPreferencesApiService(this._apiClient);

  Future<NotificationPreferencesDto?> get() async {
    try {
      final r = await _apiClient.dio.get('notification-preferences/');
      return NotificationPreferencesDto.fromJson(
        r.data as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      debugPrint('NotifPrefsApi: GET failed: ${e.message}');
      return null;
    }
  }

  Future<NotificationPreferencesDto?> patch({
    bool? pushEnabled,
    NotifPreset? preset,
    NotifTimeSlot? timeSlot,
    String? timezone,
    int? refusalCount,
    DateTime? lastRefusalAt,
    DateTime? lastRenudgeAt,
    int? renudgeShownCount,
    bool? modalSeen,
    bool? notifVeilleEnabled,
  }) async {
    final body = <String, dynamic>{};
    if (pushEnabled != null) body['push_enabled'] = pushEnabled;
    if (preset != null) body['preset'] = preset.wire;
    if (timeSlot != null) body['time_slot'] = timeSlot.wire;
    if (timezone != null) body['timezone'] = timezone;
    if (refusalCount != null) body['refusal_count'] = refusalCount;
    if (lastRefusalAt != null) {
      body['last_refusal_at'] = lastRefusalAt.toUtc().toIso8601String();
    }
    if (lastRenudgeAt != null) {
      body['last_renudge_at'] = lastRenudgeAt.toUtc().toIso8601String();
    }
    if (renudgeShownCount != null) {
      body['renudge_shown_count'] = renudgeShownCount;
    }
    if (modalSeen != null) body['modal_seen'] = modalSeen;
    if (notifVeilleEnabled != null) {
      body['notif_veille_enabled'] = notifVeilleEnabled;
    }

    if (body.isEmpty) return null;

    try {
      final r = await _apiClient.dio.patch(
        'notification-preferences/',
        data: body,
      );
      return NotificationPreferencesDto.fromJson(
        r.data as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      debugPrint('NotifPrefsApi: PATCH failed: ${e.message}');
      return null;
    }
  }
}
