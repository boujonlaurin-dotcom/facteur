import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:flutter_timezone/flutter_timezone.dart';

/// Service de notifications push locales pour le digest quotidien.
///
/// Planifie une notification quotidienne à 8h Europe/Paris pour rappeler
/// à l'utilisateur que son digest est prêt. Pas de FCM — local uniquement.
class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService _instance = PushNotificationService._();

  factory PushNotificationService() => _instance;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Référence au navigateur global pour la navigation au tap
  static GlobalKey<NavigatorState>? _navigatorKey;

  bool _initialized = false;

  /// Configure le navigatorKey pour la navigation au tap notification
  static void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  /// Initialise le plugin de notifications et les timezones.
  Future<void> init() async {
    if (_initialized) return;

    // Initialiser les données de timezone
    tz_data.initializeTimeZones();

    // Détecter le fuseau horaire local du device
    try {
      final timeZoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZoneName));
    } catch (e) {
      debugPrint('PushNotificationService: Could not detect timezone: $e');
      // Fallback sur Europe/Paris (notre cible principale)
      tz.setLocalLocation(tz.getLocation('Europe/Paris'));
    }

    // Configuration Android
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // Configuration iOS
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    // Initialiser avec le handler de tap (v20: named parameter 'settings:')
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    _initialized = true;
    debugPrint('PushNotificationService: Initialized successfully');
  }

  /// Demande la permission de notifications (Android 13+).
  /// Sur iOS, la permission est demandée via DarwinInitializationSettings.
  Future<bool> requestPermission() async {
    // Android 13+ nécessite une permission runtime
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      final granted =
          await androidPlugin.requestNotificationsPermission() ?? false;
      debugPrint(
          'PushNotificationService: Android notification permission: $granted');
      return granted;
    }

    // iOS: permission demandée automatiquement lors de l'init
    return true;
  }

  /// Planifie la notification quotidienne de digest à 8h Europe/Paris.
  /// Utilise [matchDateTimeComponents: DateTimeComponents.time] pour la répétition.
  Future<void> scheduleDailyDigestNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'digest_channel',
      'Digest quotidien',
      channelDescription:
          'Notification quotidienne quand votre digest est prêt',
      importance: Importance.high,
      priority: Priority.high,
    );

    const iosDetails = DarwinNotificationDetails();

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final scheduledDate = _nextInstanceOf8AM();

    // v20: ALL parameters are named
    await _plugin.zonedSchedule(
      id: 0,
      title: 'Votre digest est prêt !',
      body: '5 articles sélectionnés pour vous ce matin',
      scheduledDate: scheduledDate,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );

    debugPrint(
      'PushNotificationService: Daily digest notification scheduled for $scheduledDate',
    );
  }

  /// Annule la notification de digest (ID 0).
  Future<void> cancelDigestNotification() async {
    await _plugin.cancel(id: 0);
    debugPrint('PushNotificationService: Digest notification cancelled');
  }

  /// Calcule la prochaine occurrence de 8h00 Europe/Paris.
  tz.TZDateTime _nextInstanceOf8AM() {
    final paris = tz.getLocation('Europe/Paris');
    final now = tz.TZDateTime.now(paris);
    var scheduledDate = tz.TZDateTime(paris, now.year, now.month, now.day, 8);

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    return scheduledDate;
  }

  /// Handler de tap sur la notification — navigue vers le DigestScreen.
  static void _onNotificationTapped(NotificationResponse response) {
    debugPrint(
      'PushNotificationService: Notification tapped (id: ${response.id})',
    );

    // Naviguer vers le DigestScreen via le navigatorKey
    final navigator = _navigatorKey?.currentState;
    if (navigator != null) {
      navigator.pushNamedAndRemoveUntil('/digest', (route) => false);
    } else {
      debugPrint(
        'PushNotificationService: Navigator key not available, cannot navigate',
      );
    }
  }
}
