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
import 'posthog_service.dart';
import 'push_notification_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // Push Android = data-only (cf. push_dispatcher._send_fcm) : le système ne
  // rend rien tout seul, c'est ici qu'on construit la notif à bullets depuis
  // `data['teasers']`. Réutilise le chemin de rendu foreground
  // (cf. bug-notif-matin-avatar-double-sans-bullets, Part 2).
  try {
    final service = PushNotificationService();
    await service.init();
    await service.showRemoteNotification(message);
  } catch (e) {
    debugPrint('ServerPushService: background render failed: $e');
  }
}

class ServerPushService {
  ServerPushService._();

  static final ServerPushService instance = ServerPushService._();
  static const serverRegisteredKey = 'notif_server_device_registered';
  static const _deviceIdKey = 'push_device_id';

  /// Clés Hive (box `settings`) des teasers Essentiel persistés pour le
  /// fallback local (notif digest en variantB quand le push serveur est
  /// indisponible). Source = dernier fetch du Flux Continu.
  static const essentielTeasersKey = 'notif_essentiel_teasers';
  static const essentielSereneKey = 'notif_essentiel_serene';

  /// Lecture défensive des teasers Essentiel persistés. Hive rend des
  /// `List<dynamic>` ; on filtre aux `String` non vides pour éviter un crash de
  /// cast. Partagée par les 3 chemins de fallback (this, provider, main.dart).
  static List<String> readEssentielTeasers(Box<dynamic> box) {
    final raw = box.get(essentielTeasersKey);
    if (raw is! List) return const [];
    return raw
        .whereType<String>()
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList(growable: false);
  }

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
      if (token == null) {
        // FCM n'a pas pu produire de token : typiquement un
        // `google-services.json` absent/incohérent pour le flavor courant.
        // C'est l'un des deux suspects « 0 device » (cf. Part 2).
        unawaited(_capturePushRegister(outcome: 'token_null'));
        return _setRegistered(false);
      }
      return _registerToken(token);
    } catch (e) {
      debugPrint('ServerPushService: initialization failed: $e');
      unawaited(
        _capturePushRegister(outcome: 'exception', reason: e.runtimeType.toString()),
      );
      await _setRegistered(false);
      await _restoreGenericFallback();
      return false;
    }
  }

  Future<bool> _registerToken(String token) async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) {
      // Token FCM présent mais pas de session Supabase au moment de l'appel.
      // Mitigé par le listener onAuthStateChange (main.dart), mais on trace le
      // cas pour distinguer cette course du suspect config (cf. Part 2).
      unawaited(_capturePushRegister(outcome: 'session_null'));
      return _setRegistered(false);
    }

    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString(_deviceIdKey);
    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await prefs.setString(_deviceIdKey, deviceId);
    }
    final timezone = await FlutterTimezone.getLocalTimezone();
    final package = await PackageInfo.fromPlatform();
    final api = PushDevicesApiService(ApiClient(Supabase.instance.client));
    final result = await api.upsert(
      deviceId: deviceId,
      token: token,
      platform: Platform.isIOS ? 'ios' : 'android',
      timezone: timezone,
      appVersion: '${package.version}+${package.buildNumber}',
    );
    final registered = result.ok;
    // Le 503 ici = `FIREBASE_SERVICE_ACCOUNT_*` non configuré côté backend
    // Railway (l'autre suspect « 0 device » avec token_null). Le status_code
    // est tracé pour trancher le diagnostic après release (cf. Part 2).
    unawaited(_capturePushRegister(
      outcome: registered ? 'registered' : 'endpoint_error',
      statusCode: result.statusCode,
    ));
    await _setRegistered(registered);
    if (registered) {
      // Le push serveur prend le relais : on annule la notif locale planifiée.
      // Les teasers Essentiel persistés en Hive sont conservés — ils servent de
      // fallback si la registration serveur se perd plus tard
      // (cf. bug-notif-matin-avatar-double-sans-bullets, Part 1).
      await PushNotificationService().cancelDigestNotification();
    } else {
      await _restoreGenericFallback();
    }
    return registered;
  }

  /// Trace l'issue de l'enregistrement push serveur pour PostHog. Permet de
  /// trancher la cause racine « 0 device » après une release :
  /// - `token_null` → `google-services.json` du flavor (config app/CI) ;
  /// - `endpoint_error` + `status_code: 503` → `FIREBASE_SERVICE_ACCOUNT_*`
  ///   non configuré sur le backend Railway ;
  /// - `session_null` → course session/boot ; `registered` → succès.
  Future<void> _capturePushRegister({
    required String outcome,
    int? statusCode,
    String? reason,
  }) async {
    await PostHogService().capture(
      event: 'push_register',
      properties: {
        'outcome': outcome,
        'platform': Platform.isIOS ? 'ios' : 'android',
        if (statusCode != null) 'status_code': statusCode,
        if (reason != null) 'reason': reason,
      },
    );
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
    final teasers = readEssentielTeasers(box);
    final serene = box.get(essentielSereneKey, defaultValue: false) as bool;
    // Pas de demande exact-alarm automatique ici (rejouée à chaque FCM raté →
    // pop-up « Alarmes et rappels » intempestif, cf. bug-modals-intrusives).
    // Planification directe : retombe en mode inexact si la permission manque.
    // variantB + teasers (bullets) si on a un dernier digest, sinon variantA.
    await localPush.scheduleDailyDigestNotification(
      timeSlot: slot,
      variant: teasers.isEmpty ? NotifVariant.variantA : NotifVariant.variantB,
      teasers: teasers.isEmpty ? null : teasers,
      serene: serene,
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
