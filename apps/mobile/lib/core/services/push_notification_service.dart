import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:flutter_timezone/flutter_timezone.dart';

import '../api/notification_preferences_api_service.dart';

/// Variante de copy de la notification quotidienne.
///
/// - [variantA] : copy par défaut sans teaser éditorial.
/// - [variantB] : copy avec teaser (titre du sujet phare).
/// - [variantC] : *jour calme* — déclenchement manuel uniquement (hors v1).
enum NotifVariant { variantA, variantB, variantC }

/// IDs réservés pour les notifications planifiées (un ID = un slot dans
/// `pendingNotificationRequests`). Garder stable pour permettre `cancel(id)`.
class _NotifIds {
  static const dailyDigest = 0;
  static const weeklyCommunityPick = 1;
}

/// Service de notifications push locales (FCM non utilisé en v1).
class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService _instance = PushNotificationService._();

  factory PushNotificationService() => _instance;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static GlobalKey<NavigatorState>? _navigatorKey;

  bool _initialized = false;

  static void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  Future<void> init() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();

    try {
      final timeZoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZoneName));
    } catch (e) {
      debugPrint('PushNotificationService: Could not detect timezone: $e');
      tz.setLocalLocation(tz.getLocation('Europe/Paris'));
    }

    // Small icon: monochrome silhouette, blanc sur transparent. ic_launcher_foreground
    // est un fallback v1 — remplacer par @drawable/ic_stat_facteur dès que l'asset
    // dédié est fourni (cf plan §3 Icône notif).
    const androidSettings =
        AndroidInitializationSettings('@drawable/ic_launcher_foreground');

    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    _initialized = true;
    debugPrint('PushNotificationService: Initialized successfully');
  }

  Future<bool> requestPermission() async {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      final granted =
          await androidPlugin.requestNotificationsPermission() ?? false;
      debugPrint(
          'PushNotificationService: Android notification permission: $granted');
      return granted;
    }
    return true;
  }

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
      return true;
    }
    return true;
  }

  Future<bool> ensureExactAlarmPermission() async {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return true;
    final canSchedule =
        await androidPlugin.canScheduleExactNotifications() ?? false;
    if (canSchedule) return true;
    return await androidPlugin.requestExactAlarmsPermission() ?? false;
  }

  // --- Copy variants -------------------------------------------------------

  /// Variante A — défaut, sans teaser éditorial.
  static const String defaultTitle = 'Facteur passé !';
  static const String defaultBody = "Ton récap du jour t'attend.";

  /// Variante C — déclenchée manuellement par l'éditorial (hors v1).
  static const String calmTitle = 'Facteur passé !';
  static const String calmBody =
      "Rien d'important dans l'actu aujourd'hui. Belle journée !";

  /// Pépite communauté hebdo (vendredi 18:00, préset Curieux).
  static const String communityTitle = 'Facteur passé !';
  static const String communityBody =
      "Les Fact·eur·isses adorent cet article. Jette-y un œil quand tu as 2 min !";

  /// Construit le couple (title, body) selon la variante.
  ///
  /// - [variantB] requiert [teaser] (titre du sujet phare). Tronqué à 60c
  ///   pour respecter le brief §6.1.
  static ({String title, String body}) buildCopy({
    required NotifVariant variant,
    String? teaser,
  }) {
    switch (variant) {
      case NotifVariant.variantA:
        return (title: defaultTitle, body: defaultBody);
      case NotifVariant.variantB:
        if (teaser == null || teaser.trim().isEmpty) {
          return (title: defaultTitle, body: defaultBody);
        }
        final trimmed = teaser.trim();
        final clipped = trimmed.length > 60
            ? '${trimmed.substring(0, 57)}…'
            : trimmed;
        return (
          title: 'Je suis passé.',
          body: 'À la une : $clipped',
        );
      case NotifVariant.variantC:
        return (title: calmTitle, body: calmBody);
    }
  }

  // --- Daily digest --------------------------------------------------------

  /// Planifie la notification quotidienne à l'heure correspondant à [timeSlot].
  ///
  /// Si [variant] vaut [NotifVariant.variantB], [teaser] est utilisé comme sujet
  /// phare. Sinon, fallback variante A.
  Future<bool> scheduleDailyDigestNotification({
    NotifTimeSlot timeSlot = NotifTimeSlot.morning,
    NotifVariant variant = NotifVariant.variantA,
    String? teaser,
  }) async {
    final time = _timeOfDayFor(timeSlot);
    final scheduledDate = _nextInstanceOf(time);
    final copy = buildCopy(variant: variant, teaser: teaser);

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final canUseExact =
        (await androidPlugin?.canScheduleExactNotifications()) ?? true;
    final scheduleMode = canUseExact
        ? AndroidScheduleMode.alarmClock
        : AndroidScheduleMode.inexactAllowWhileIdle;

    final androidDetails = AndroidNotificationDetails(
      'digest_channel',
      'Digest quotidien',
      channelDescription:
          'Notification quotidienne quand ton récap est prêt',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_launcher_foreground',
      styleInformation: BigTextStyleInformation(
        copy.body,
        contentTitle: copy.title,
      ),
    );
    const iosDetails = DarwinNotificationDetails();

    await _plugin.zonedSchedule(
      id: _NotifIds.dailyDigest,
      title: copy.title,
      body: copy.body,
      scheduledDate: scheduledDate,
      notificationDetails: NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
      androidScheduleMode: scheduleMode,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'route:/digest',
    );

    debugPrint(
      'PushNotificationService: daily scheduled @ $scheduledDate '
      '(variant: $variant, slot: $timeSlot)',
    );

    return _isScheduled(_NotifIds.dailyDigest);
  }

  /// Planifie la pépite communauté tous les vendredis à 18:00 (préset Curieux).
  ///
  /// [articleId] est joint au payload pour permettre l'ouverture directe de
  /// l'article au tap. Si null, l'app retombe sur le digest.
  Future<bool> scheduleWeeklyCommunityPick({String? articleId}) async {
    final scheduledDate = _nextInstanceOfWeekday(
      weekday: DateTime.friday,
      time: const TimeOfDay(hour: 18, minute: 0),
    );

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final canUseExact =
        (await androidPlugin?.canScheduleExactNotifications()) ?? true;
    final scheduleMode = canUseExact
        ? AndroidScheduleMode.alarmClock
        : AndroidScheduleMode.inexactAllowWhileIdle;

    final androidDetails = AndroidNotificationDetails(
      'community_channel',
      'Pépite communauté',
      channelDescription:
          'Recommandation hebdomadaire des Fact·eur·isses',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_launcher_foreground',
      styleInformation: BigTextStyleInformation(
        communityBody,
        contentTitle: communityTitle,
      ),
    );
    const iosDetails = DarwinNotificationDetails();

    await _plugin.zonedSchedule(
      id: _NotifIds.weeklyCommunityPick,
      title: communityTitle,
      body: communityBody,
      scheduledDate: scheduledDate,
      notificationDetails: NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
      androidScheduleMode: scheduleMode,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      payload: articleId != null ? 'route:/article/$articleId' : 'route:/digest',
    );

    debugPrint(
      'PushNotificationService: weekly community scheduled @ $scheduledDate',
    );

    return _isScheduled(_NotifIds.weeklyCommunityPick);
  }

  Future<bool> _isScheduled(int id) async {
    final pending = await _plugin.pendingNotificationRequests();
    return pending.any((n) => n.id == id);
  }

  Future<bool> isDigestNotificationScheduled() =>
      _isScheduled(_NotifIds.dailyDigest);

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

    return {
      'initialized': _initialized,
      'platform': defaultTargetPlatform.name,
      'notificationsEnabled': notificationsEnabled,
      'exactAlarmsGranted': exactAlarmsGranted,
      'digestScheduled': pending.any((n) => n.id == _NotifIds.dailyDigest),
      'communityScheduled':
          pending.any((n) => n.id == _NotifIds.weeklyCommunityPick),
      'pendingCount': pending.length,
    };
  }

  Future<void> cancelDigestNotification() async {
    await _plugin.cancel(id: _NotifIds.dailyDigest);
  }

  Future<void> cancelWeeklyCommunityPick() async {
    await _plugin.cancel(id: _NotifIds.weeklyCommunityPick);
  }

  // --- Time helpers --------------------------------------------------------

  static TimeOfDay _timeOfDayFor(NotifTimeSlot slot) => switch (slot) {
        NotifTimeSlot.morning => const TimeOfDay(hour: 7, minute: 30),
        NotifTimeSlot.evening => const TimeOfDay(hour: 19, minute: 0),
      };

  tz.TZDateTime _nextInstanceOf(TimeOfDay time) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  tz.TZDateTime _nextInstanceOfWeekday({
    required int weekday,
    required TimeOfDay time,
  }) {
    var scheduled = _nextInstanceOf(time);
    while (scheduled.weekday != weekday) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  static void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    debugPrint(
      'PushNotificationService: tapped (id: ${response.id}, payload: $payload)',
    );

    final navigator = _navigatorKey?.currentState;
    if (navigator == null) return;

    final route = _routeFromPayload(payload);
    navigator.pushNamedAndRemoveUntil(route, (_) => false);
  }

  static String _routeFromPayload(String? payload) {
    if (payload == null || !payload.startsWith('route:')) return '/digest';
    return payload.substring('route:'.length);
  }
}
