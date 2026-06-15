import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../api/notification_preferences_api_service.dart';
import '../api/push_devices_api_service.dart';
import 'push_notification_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class ServerPushService {
  ServerPushService._();

  static final ServerPushService instance = ServerPushService._();
  static const serverRegisteredKey = 'notif_server_device_registered';
  static const _deviceIdKey = 'push_device_id';

  // Singleton vivant pendant toute la durée du process.
  // ignore: cancel_subscriptions
  StreamSubscription<String>? _tokenSubscription;
  bool _initialized = false;

  Future<bool> initAndRegister() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return false;
    try {
      if (!_initialized) {
        await Firebase.initializeApp();
        FirebaseMessaging.onBackgroundMessage(
          firebaseMessagingBackgroundHandler,
        );
        await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        FirebaseMessaging.onMessage.listen((message) {
          unawaited(
            PushNotificationService().showRemoteNotification(message),
          );
        });
        FirebaseMessaging.onMessageOpenedApp.listen(_openMessage);
        final initial = await FirebaseMessaging.instance.getInitialMessage();
        if (initial != null) _openMessage(initial);
        _tokenSubscription ??=
            FirebaseMessaging.instance.onTokenRefresh.listen((token) {
          unawaited(_registerToken(token));
        });
        _initialized = true;
      }

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return _setRegistered(false);
      return _registerToken(token);
    } catch (e) {
      debugPrint('ServerPushService: initialization failed: $e');
      await _setRegistered(false);
      await _restoreGenericFallback();
      return false;
    }
  }

  Future<bool> _registerToken(String token) async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return _setRegistered(false);

    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString(_deviceIdKey);
    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await prefs.setString(_deviceIdKey, deviceId);
    }
    final timezone = await FlutterTimezone.getLocalTimezone();
    final package = await PackageInfo.fromPlatform();
    final api = PushDevicesApiService(ApiClient(Supabase.instance.client));
    final registered = await api.upsert(
      deviceId: deviceId,
      token: token,
      platform: Platform.isIOS ? 'ios' : 'android',
      timezone: timezone,
      appVersion: '${package.version}+${package.buildNumber}',
    );
    await _setRegistered(registered);
    if (registered) {
      await PushNotificationService().cancelDigestNotification();
      final box = await Hive.openBox<dynamic>('settings');
      await box.delete('notif_essentiel_teasers');
    } else {
      await _restoreGenericFallback();
    }
    return registered;
  }

  Future<void> revokeCurrentDevice() async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getString(_deviceIdKey);
    if (deviceId != null &&
        Supabase.instance.client.auth.currentSession != null) {
      await PushDevicesApiService(ApiClient(Supabase.instance.client))
          .revoke(deviceId);
    }
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      debugPrint('ServerPushService: deleteToken failed: $e');
    }
    await _setRegistered(false);
  }

  Future<void> _restoreGenericFallback() async {
    final box = await Hive.openBox<dynamic>('settings');
    final enabled =
        box.get('push_notifications_enabled', defaultValue: false) as bool;
    if (!enabled) return;
    final slot = NotifTimeSlotX.fromWire(box.get('notif_time_slot') as String?);
    final localPush = PushNotificationService();
    await localPush.ensureExactAlarmPermission();
    await localPush.scheduleDailyDigestNotification(
      timeSlot: slot,
      variant: NotifVariant.variantA,
    );
  }

  Future<bool> _setRegistered(bool value) async {
    final box = await Hive.openBox<dynamic>('settings');
    await box.put(serverRegisteredKey, value);
    return value;
  }

  void _openMessage(RemoteMessage message) {
    final route = message.data['route'] as String? ?? '/digest';
    PushNotificationService.openRoute(route);
  }
}
