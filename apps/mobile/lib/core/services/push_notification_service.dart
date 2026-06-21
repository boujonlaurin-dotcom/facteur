import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:hive_flutter/hive_flutter.dart';
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
  static const dailyGoodNews = 2;
  static const veilleDelivery = 3;
}

/// Notifications locales, y compris l'affichage au premier plan des pushes FCM.
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

    // Small icon: silhouette monochrome dédiée — Android exige un asset
    // blanc/alpha pour la status bar (sinon bloc coloré mal dimensionné).
    const androidSettings =
        AndroidInitializationSettings('@drawable/ic_stat_facteur');

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

  /// Clé Hive (box `settings`) : marque qu'on a déjà ouvert au moins une fois
  /// l'écran système « Alarmes et rappels ». Garde one-shot pour les chemins
  /// automatiques — le pop-up ne doit jamais se rouvrir tout seul après un 1er
  /// refus (cf. bug-modals-intrusives).
  static const exactAlarmAskedKey = 'notif_exact_alarm_asked';

  /// Ouvre l'écran système Android « Alarmes et rappels » pour demander la
  /// permission d'alarme exacte (une `Activity` séparée).
  ///
  /// [userInitiated] : `true` UNIQUEMENT quand l'appel découle d'une action
  /// utilisateur explicite (modal d'activation, toggle Réglages) — l'écran OS
  /// est alors (ré)ouvert même après un refus précédent. `false` (défaut) pour
  /// tout chemin automatique : une garde Hive one-shot ([exactAlarmAskedKey])
  /// empêche de rouvrir l'écran après une 1ère demande, et la planification
  /// retombe silencieusement en mode inexact.
  Future<bool> requestExactAlarmPermission({bool userInitiated = false}) async {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return true;

    final canSchedule =
        await androidPlugin.canScheduleExactNotifications() ?? false;
    if (canSchedule) return true;

    final box = await Hive.openBox<dynamic>('settings');
    if (!userInitiated &&
        (box.get(exactAlarmAskedKey, defaultValue: false) as bool)) {
      debugPrint(
        'PushNotificationService: exact alarm already requested once - '
        'skip auto re-prompt (inexact scheduling)',
      );
      return false;
    }

    await box.put(exactAlarmAskedKey, true);
    final granted = await androidPlugin.requestExactAlarmsPermission() ?? false;
    debugPrint(
        'PushNotificationService: Exact alarm permission requested: $granted');
    return granted;
  }

  // --- Copy variants -------------------------------------------------------

  /// Nom affiché comme expéditeur dans la notif Android (MessagingStyle).
  static const String senderName = 'Ton facteur';

  /// Variante A — défaut, sans teaser éditorial.
  static const String defaultTitle = 'Facteur';
  static const String defaultBody = "Ton récap du jour t'attend quand tu veux.";

  /// En-têtes du bigText de la notif digest (variante B), selon le mode.
  static const String digestHeader = "À la une dans l'Essentiel :";
  static const String digestHeaderSerene = 'Du calme dans ton actu :';

  /// Ligne CTA finale du bigText digest, selon le mode.
  static const String digestCta =
      "Pour le reste, viens faire un tour sur l'app !";
  static const String digestCtaSerene =
      "Le reste t'attend tranquillement dans l'app.";

  /// Variante C — déclenchée manuellement par l'éditorial (hors v1).
  static const String calmTitle = 'Facteur';
  static const String calmBody =
      "Rien d'important dans l'actu aujourd'hui. Belle journée !";

  /// Pépite communauté hebdo (vendredi 18:00, préset Curieux).
  static const String communityTitle = 'Facteur';
  static const String communityBody =
      "Les Fact·eur·isses adorent cet article. Jette-y un œil quand tu as 2 min !";

  /// Bonnes nouvelles du jour — canal opt-in indépendant du digest principal.
  static const String goodNewsTitle = '🌱 Vos bonnes nouvelles du jour';
  static const String goodNewsBody =
      "Une dose d'espoir, sélectionnée avec soin.";

  /// Livraison « Ma veille » — notif locale planifiée à `next_scheduled_at + 30 min`.
  static const String veilleTitle = 'Ta veille est arrivée';
  static const String veilleBody =
      "Découvre les sujets phares de ta période, sélectionnés pour toi.";

  /// Construit le triplet (title, body, bigText) selon la variante.
  ///
  /// - [variantB] requiert au moins un teaser dans [teasers]. Le titre complet
  ///   du premier teaser est utilisé pour le body collapsed (l'OS l'ellipsise
  ///   sur une ligne) ; les 2 premiers titres sont rendus en bullets dans le
  ///   bigText Android, suivis d'une ligne CTA renvoyant vers l'app.
  /// - [serene] bascule l'en-tête et le CTA sur un ton apaisé (mode Serein).
  static ({String title, String body, String bigText}) buildCopy({
    required NotifVariant variant,
    List<String>? teasers,
    bool serene = false,
  }) {
    switch (variant) {
      case NotifVariant.variantA:
        return (title: defaultTitle, body: defaultBody, bigText: defaultBody);
      case NotifVariant.variantB:
        final cleaned = (teasers ?? const <String>[])
            .map((t) => t.trim())
            .where((t) => t.isNotEmpty)
            .take(2)
            .toList();
        if (cleaned.isEmpty) {
          return (title: defaultTitle, body: defaultBody, bigText: defaultBody);
        }
        final header = serene ? digestHeaderSerene : digestHeader;
        final cta = serene ? digestCtaSerene : digestCta;
        final bullets = cleaned.map((t) => '• $t').join('\n');
        return (
          title: defaultTitle,
          body: cleaned.first,
          bigText: '$header\n$bullets\n$cta',
        );
      case NotifVariant.variantC:
        return (title: calmTitle, body: calmBody, bigText: calmBody);
    }
  }

  /// Construit le triplet (title, body, bigText) pour la notif « Bonnes
  /// nouvelles du jour » — miroir de [buildCopy] mais ton serein.
  ///
  /// - [teasers] vide → corps générique ([goodNewsTitle] / [goodNewsBody]) ;
  /// - sinon → body collapsed avec le premier teaser (clip 60c), bigText en
  ///   bullets (max 3).
  static ({String title, String body, String bigText}) buildGoodNewsCopy({
    List<String>? teasers,
  }) {
    final cleaned = (teasers ?? const <String>[])
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .take(3)
        .toList();
    if (cleaned.isEmpty) {
      return (title: goodNewsTitle, body: goodNewsBody, bigText: goodNewsBody);
    }
    final first = cleaned.first;
    final clipped = first.length > 60 ? '${first.substring(0, 57)}…' : first;
    final bullets = cleaned.map((t) => '• $t').join('\n');
    return (
      title: goodNewsTitle,
      body: 'À la une : $clipped',
      bigText: 'Vos bonnes nouvelles du jour :\n$bullets',
    );
  }

  // --- Daily digest --------------------------------------------------------

  /// Planifie la notification quotidienne à l'heure correspondant à [timeSlot].
  ///
  /// Si [variant] vaut [NotifVariant.variantB], [teaser] est utilisé comme sujet
  /// phare. Sinon, fallback variante A.
  Future<bool> scheduleDailyDigestNotification({
    NotifTimeSlot timeSlot = NotifTimeSlot.morning,
    NotifVariant variant = NotifVariant.variantA,
    List<String>? teasers,
    bool serene = false,
  }) async {
    final time = _timeOfDayFor(timeSlot);
    final scheduledDate = _nextInstanceOf(time);
    final copy = buildCopy(variant: variant, teasers: teasers, serene: serene);

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final canUseExact =
        (await androidPlugin?.canScheduleExactNotifications()) ?? true;
    final scheduleMode = canUseExact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    const sender = Person(
      name: senderName,
      key: 'facteur',
      important: true,
    );
    final androidDetails = AndroidNotificationDetails(
      'digest_channel',
      'Digest quotidien',
      channelDescription: 'Notification quotidienne quand ton récap est prêt',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_stat_facteur',
      color: const Color(0xFFD35400),
      styleInformation: MessagingStyleInformation(
        const Person(name: 'Toi'),
        groupConversation: false,
        messages: [
          Message(copy.bigText, DateTime.now(), sender),
        ],
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
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    final androidDetails = AndroidNotificationDetails(
      'community_channel',
      'Pépite communauté',
      channelDescription: 'Recommandation hebdomadaire des Fact·eur·isses',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_stat_facteur',
      color: const Color(0xFFD35400),
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
      payload:
          articleId != null ? 'route:/article/$articleId' : 'route:/digest',
    );

    debugPrint(
      'PushNotificationService: weekly community scheduled @ $scheduledDate',
    );

    return _isScheduled(_NotifIds.weeklyCommunityPick);
  }

  /// Planifie le push « Bonnes nouvelles du jour » — canal séparé du digest
  /// principal pour permettre un horaire dédié sans coupler les opt-ins.
  Future<bool> scheduleDailyGoodNewsNotification({
    NotifTimeSlot timeSlot = NotifTimeSlot.evening,
    List<String>? teasers,
  }) async {
    final time = _timeOfDayFor(timeSlot);
    final scheduledDate = _nextInstanceOf(time);
    final copy = buildGoodNewsCopy(teasers: teasers);

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final canUseExact =
        (await androidPlugin?.canScheduleExactNotifications()) ?? true;
    final scheduleMode = canUseExact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    const sender = Person(
      name: senderName,
      key: 'facteur',
      important: true,
    );
    final androidDetails = AndroidNotificationDetails(
      'good_news_channel',
      'Bonnes nouvelles du jour',
      channelDescription:
          "Notification quotidienne des bonnes nouvelles sélectionnées",
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_stat_facteur',
      color: const Color(0xFFD35400),
      styleInformation: MessagingStyleInformation(
        const Person(name: 'Toi'),
        groupConversation: false,
        messages: [
          Message(copy.bigText, DateTime.now(), sender),
        ],
      ),
    );
    const iosDetails = DarwinNotificationDetails();

    await _plugin.zonedSchedule(
      id: _NotifIds.dailyGoodNews,
      title: copy.title,
      body: copy.body,
      scheduledDate: scheduledDate,
      notificationDetails: NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
      androidScheduleMode: scheduleMode,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'route:/digest?serein=1',
    );

    debugPrint(
      'PushNotificationService: good news scheduled @ $scheduledDate '
      '(slot: $timeSlot, teasers: ${teasers?.length ?? 0})',
    );

    return _isScheduled(_NotifIds.dailyGoodNews);
  }

  Future<void> cancelGoodNewsNotification() async {
    await _plugin.cancel(id: _NotifIds.dailyGoodNews);
  }

  Future<bool> isGoodNewsNotificationScheduled() =>
      _isScheduled(_NotifIds.dailyGoodNews);

  /// Planifie la notification locale « Ma veille » pour [scheduledAt].
  ///
  /// Le caller doit ajouter une marge (≈30 min) à `next_scheduled_at` reçu du
  /// backend pour laisser le scanner `*/30 min` générer la livraison avant
  /// que la notif ne tombe.
  ///
  /// Retourne `true` si la notif a bien été enregistrée auprès du système, ou
  /// `false` si la date est dans le passé (évite le crash sur Android, qui
  /// refuse de planifier dans le passé).
  Future<bool> scheduleVeilleNotification({
    required DateTime scheduledAt,
  }) async {
    final tzScheduled = tz.TZDateTime.from(scheduledAt, tz.local);
    if (!tzScheduled.isAfter(tz.TZDateTime.now(tz.local))) {
      debugPrint(
        'PushNotificationService: skip veille schedule — past date $scheduledAt',
      );
      return false;
    }

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final canUseExact =
        (await androidPlugin?.canScheduleExactNotifications()) ?? true;
    final scheduleMode = canUseExact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    final androidDetails = AndroidNotificationDetails(
      'veille_channel',
      'Ma veille',
      channelDescription:
          'Notification quand ta veille personnalisée est prête.',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_stat_facteur',
      color: const Color(0xFFD35400),
      styleInformation: const BigTextStyleInformation(
        veilleBody,
        contentTitle: veilleTitle,
      ),
    );
    const iosDetails = DarwinNotificationDetails();

    await _plugin.zonedSchedule(
      id: _NotifIds.veilleDelivery,
      title: veilleTitle,
      body: veilleBody,
      scheduledDate: tzScheduled,
      notificationDetails: NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
      androidScheduleMode: scheduleMode,
      payload: 'route:/flux-continu',
    );

    debugPrint(
      'PushNotificationService: veille scheduled @ $tzScheduled',
    );

    return _isScheduled(_NotifIds.veilleDelivery);
  }

  Future<void> cancelVeilleNotification() async {
    await _plugin.cancel(id: _NotifIds.veilleDelivery);
  }

  Future<bool> isVeilleNotificationScheduled() =>
      _isScheduled(_NotifIds.veilleDelivery);

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

  Future<void> showRemoteNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    final route = message.data['route'] as String? ?? '/digest';
    const androidDetails = AndroidNotificationDetails(
      'digest_channel',
      'Digest quotidien',
      channelDescription: 'Notification quotidienne quand ton récap est prêt',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_stat_facteur',
      color: Color(0xFFD35400),
    );
    const iosDetails = DarwinNotificationDetails();
    await _plugin.show(
      id: message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch,
      title: notification.title ?? defaultTitle,
      body: notification.body ?? defaultBody,
      notificationDetails: const NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
      payload: 'route:$route',
    );
  }

  static void openRoute(String route) {
    final navigator = _navigatorKey?.currentState;
    if (navigator == null) return;
    navigator.pushNamedAndRemoveUntil(route, (_) => false);
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

    final route = _routeFromPayload(payload);
    openRoute(route);
  }

  static String _routeFromPayload(String? payload) {
    if (payload == null || !payload.startsWith('route:')) {
      return '/flux-continu';
    }
    return payload.substring('route:'.length);
  }
}
