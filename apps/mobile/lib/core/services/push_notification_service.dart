import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:flutter_timezone/flutter_timezone.dart';

/// Service de notifications push locales pour le digest quotidien.
///
/// Planifie une notification quotidienne à 8h Europe/Paris pour rappeler
/// à l'utilisateur que son digest est prêt. Pas de FCM — local uniquement.
///
/// Le contenu de la notification peut être mis à jour dynamiquement
/// avec les topics du digest via [scheduleDailyDigestNotification].
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

  /// Demande la permission d'alarmes exactes (Android 14+/API 34+).
  /// Nécessaire pour AndroidScheduleMode.alarmClock avec targetSdk >= 34.
  Future<bool> requestExactAlarmPermission() async {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      final canSchedule =
          await androidPlugin.canScheduleExactNotifications() ?? false;
      if (!canSchedule) {
        final granted =
            await androidPlugin.requestExactAlarmsPermission() ?? false;
        debugPrint(
            'PushNotificationService: Exact alarm permission requested: $granted');
        return granted;
      }
      debugPrint(
          'PushNotificationService: Exact alarm permission already granted');
      return true;
    }
    return true; // Not Android
  }

  /// Vérifie et demande la permission exact alarm si nécessaire.
  /// Appelé au startup pour s'assurer que la permission n'a pas été révoquée.
  Future<bool> ensureExactAlarmPermission() async {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return true; // Not Android

    final canSchedule =
        await androidPlugin.canScheduleExactNotifications() ?? false;
    if (canSchedule) return true;

    // Permission révoquée ou jamais accordée — demander
    debugPrint(
        'PushNotificationService: Exact alarm permission lost, re-requesting');
    final granted =
        await androidPlugin.requestExactAlarmsPermission() ?? false;
    debugPrint(
        'PushNotificationService: Exact alarm re-request result: $granted');
    return granted;
  }

  static const String defaultTitle = 'Ton Essentiel Facteur est prêt !';
  static const String defaultBody = 'Tes sujets du jour t\'attendent';

  /// Construit le body de la notification à partir des labels de topics du digest.
  ///
  /// Mode normal  → "Au programme : Trump, Retraites, Chômage... Ou rester serein ;-)"
  /// Mode serein  → "Prends un moment pour toi — tes sujets du jour t'attendent."
  ///                (ou avec les topics : "Au programme : Trump, Retraites... À lire quand tu veux.")
  ///
  /// Retourne [defaultBody] si la liste est vide.
  static String buildNotificationBody(
    List<String> topicLabels, {
    bool serein = false,
  }) {
    if (serein) {
      if (topicLabels.isEmpty) {
        return 'Prends un moment pour toi — ton digest t\'attend quand tu veux.';
      }
      final displayLabels = topicLabels.take(3).toList();
      final topicsText = displayLabels.join(', ');
      return 'Au programme : $topicsText — à lire quand tu veux, sans pression.';
    }

    if (topicLabels.isEmpty) return defaultBody;

    // Prendre les 3 premiers topics max pour rester concis
    final displayLabels = topicLabels.take(3).toList();
    final topicsText = displayLabels.join(', ');
    return 'Au programme : $topicsText... Ou rester serein ;-)';
  }

  /// Planifie la notification quotidienne de digest à 8h Europe/Paris.
  /// Utilise alarmClock (le plus fiable) avec fallback sur inexactAllowWhileIdle.
  /// Retourne true si la notification est effectivement planifiée.
  ///
  /// [body] optionnel — permet de personnaliser le message avec les topics du digest.
  /// Si null, utilise [defaultBody].
  Future<bool> scheduleDailyDigestNotification({String? body}) async {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    bool canUseExact = true;
    if (androidPlugin != null) {
      canUseExact =
          await androidPlugin.canScheduleExactNotifications() ?? false;
    }

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
    final notificationBody = body ?? defaultBody;

    // alarmClock est le plus fiable (pas affecté par Doze ni battery optimization OEM)
    // Fallback sur inexactAllowWhileIdle si la permission exacte est refusée
    final scheduleMode = canUseExact
        ? AndroidScheduleMode.alarmClock
        : AndroidScheduleMode.inexactAllowWhileIdle;

    // v20: ALL parameters are named
    await _plugin.zonedSchedule(
      id: 0,
      title: defaultTitle,
      body: notificationBody,
      scheduledDate: scheduledDate,
      notificationDetails: details,
      androidScheduleMode: scheduleMode,
      matchDateTimeComponents: DateTimeComponents.time,
    );

    debugPrint(
      'PushNotificationService: Scheduled for $scheduledDate (mode: $scheduleMode, exact: $canUseExact, body: "$notificationBody")',
    );

    // Vérifier que la notification est bien dans la liste pending
    final isScheduled = await isDigestNotificationScheduled();
    if (!isScheduled) {
      debugPrint(
        'PushNotificationService: WARNING — notification NOT found in pending list after scheduling!',
      );
    }

    return isScheduled;
  }

  /// Vérifie si la notification digest (id=0) est dans la liste des notifications pending.
  Future<bool> isDigestNotificationScheduled() async {
    final pending = await _plugin.pendingNotificationRequests();
    return pending.any((n) => n.id == 0);
  }

  /// Retourne l'état complet du système de notifications pour diagnostic.
  Future<Map<String, dynamic>> getDiagnostics() async {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    bool? notificationsEnabled;
    bool? exactAlarmsGranted;

    if (androidPlugin != null) {
      notificationsEnabled =
          await androidPlugin.areNotificationsEnabled() ?? false;
      exactAlarmsGranted =
          await androidPlugin.canScheduleExactNotifications() ?? false;
    }

    final pending = await _plugin.pendingNotificationRequests();
    final digestScheduled = pending.any((n) => n.id == 0);
    final nextScheduledDate = _nextInstanceOf8AM();

    return {
      'initialized': _initialized,
      'platform': defaultTargetPlatform.name,
      'notificationsEnabled': notificationsEnabled,
      'exactAlarmsGranted': exactAlarmsGranted,
      'digestScheduled': digestScheduled,
      'pendingCount': pending.length,
      'nextScheduledDate': nextScheduledDate.toString(),
    };
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
