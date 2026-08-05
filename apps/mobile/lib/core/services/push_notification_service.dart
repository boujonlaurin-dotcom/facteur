import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:flutter_timezone/flutter_timezone.dart';

import '../../config/routes.dart';
import '../../features/flux_continu/services/tournee_progress_service.dart';
import '../api/notification_preferences_api_service.dart';
import 'posthog_service.dart';

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

  /// Legacy — la pépite communauté hebdo n'est plus planifiée, mais l'ID reste
  /// réservé le temps que les installs existantes purgent la notif déjà posée.
  static const weeklyCommunityPick = 1;
  static const dailyGoodNews = 2;
  static const veilleDelivery = 3;

  /// Base des alertes source rare : l'ID réel vaut `sourceAlertBase + hash`,
  /// jamais une valeur fixe (cf. `_showAlert`).
  static const sourceAlertBase = 1000;
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

    // Permission iOS demandée explicitement (cf. requestPermission), JAMAIS au
    // boot : le pop-up système ne s'affiche qu'une fois par install, et
    // `init()` tourne pendant l'onboarding. Le déclencher ici brûlerait
    // l'unique demande avant l'écran d'amorce (étape 3/4) et avant la modale
    // d'activation quotidienne. On garde donc les 3 flags à `false`.
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
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
    // iOS : la demande n'est plus faite au boot (cf. DarwinInitializationSettings
    // à `false`). On déclenche donc explicitement le pop-up système ici — il ne
    // s'affiche qu'une fois, l'appel est un no-op idempotent si déjà décidé.
    final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (iosPlugin != null) {
      final granted = await iosPlugin.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
      debugPrint(
          'PushNotificationService: iOS notification permission: $granted');
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

  /// Variante A — défaut, sans teaser éditorial.
  static const String defaultTitle = 'Facteur';
  static const String defaultBody = "Ton récap du jour t'attend quand tu veux.";

  /// Ligne CTA finale du bigText digest.
  static const String digestCta = 'La suite dans Facteur !';

  /// Variante C — déclenchée manuellement par l'éditorial (hors v1).
  static const String calmTitle = 'Facteur';
  static const String calmBody =
      "Rien d'important dans l'actu aujourd'hui. Belle journée !";

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
  ///   bigText Android, suivis d'une ligne vide puis d'une ligne CTA renvoyant
  ///   vers l'app.
  static ({String title, String body, String bigText}) buildCopy({
    required NotifVariant variant,
    List<String>? teasers,
    bool serene = false,
    String? intro,
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
        final bullets = cleaned.map((t) => '• $t').join('\n');
        return (
          title: defaultTitle,
          body: cleaned.first,
          bigText: '$bullets\n\n$digestCta',
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

    final androidDetails = AndroidNotificationDetails(
      'digest_channel',
      'Digest quotidien',
      channelDescription: 'Notification quotidienne quand ton récap est prêt',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_stat_facteur',
      color: const Color(0xFFD35400),
      // BigText (et non MessagingStyle) : le multi-ligne est rendu sans avatar
      // par message — un MessagingStyle sans icône d'expéditeur produit un
      // monogramme « T » coloré dupliqué à côté de l'icône launcher
      // (cf. bug-notif-matin-avatar-double-sans-bullets).
      styleInformation: BigTextStyleInformation(
        copy.bigText,
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

    final androidDetails = AndroidNotificationDetails(
      'good_news_channel',
      'Bonnes nouvelles du jour',
      channelDescription:
          "Notification quotidienne des bonnes nouvelles sélectionnées",
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_stat_facteur',
      color: const Color(0xFFD35400),
      // BigText (et non MessagingStyle) : évite l'avatar monogramme dupliqué
      // (cf. bug-notif-matin-avatar-double-sans-bullets).
      styleInformation: BigTextStyleInformation(
        copy.bigText,
        contentTitle: copy.title,
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
      'pendingCount': pending.length,
    };
  }

  Future<void> cancelDigestNotification() async {
    await _plugin.cancel(id: _NotifIds.dailyDigest);
  }

  /// Purge la pépite communauté hebdo, retirée du produit.
  ///
  /// Supprimer le code de planification n'annule PAS la notif déjà posée : les
  /// installs existantes ont un slot armé pour le prochain vendredi 18:00 et
  /// continueraient de sonner. Ce `cancel` est le seul chemin qui les nettoie.
  Future<void> cancelLegacyCommunityPick() async {
    await _plugin.cancel(id: _NotifIds.weeklyCommunityPick);
  }

  Future<void> showRemoteNotification(RemoteMessage message) async {
    final notification = message.notification;
    final data = message.data;
    final route = data['route'] as String? ?? '/digest';

    // Le push digest est data-only sur Android (cf. push_dispatcher._send_fcm) :
    // `message.notification` est null et c'est NOUS qui rendons la notif. On
    // ignore donc le push uniquement s'il n'y a ni bloc `notification`, ni
    // données exploitables (teasers / title|body dans `data`).
    final teasers = _parseTeasers(data['teasers']);
    final dataTitle = data['title'] as String?;
    final dataBody = data['body'] as String?;
    if (notification == null &&
        teasers.isEmpty &&
        dataTitle == null &&
        dataBody == null) {
      return;
    }

    // Alertes source et sujet (stories 30.2/30.3) : canal et ID dédiés, jamais
    // le canal digest — elles doivent arriver sans son ni vibration.
    if (data['kind'] == 'source_alert' || data['kind'] == 'topic_alert') {
      await _showAlert(data, notification: notification);
      return;
    }

    // Si le push porte des teasers (`data['teasers']` = JSON liste de titres),
    // on rend de vrais bullets (variantB) au lieu du corps une-ligne. Sinon,
    // fallback sur le bloc `notification` FCM, puis sur `data` title/body.
    final String title;
    final String body;
    final String bigText;
    if (teasers.isNotEmpty) {
      final copy = buildCopy(
        variant: NotifVariant.variantB,
        teasers: teasers,
        intro: data['intro'] as String?,
      );
      title = copy.title;
      body = copy.body;
      bigText = copy.bigText;
    } else {
      title = notification?.title ?? dataTitle ?? defaultTitle;
      body = notification?.body ?? dataBody ?? defaultBody;
      bigText = body;
    }

    final androidDetails = AndroidNotificationDetails(
      'digest_channel',
      'Digest quotidien',
      channelDescription: 'Notification quotidienne quand ton récap est prêt',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_stat_facteur',
      color: const Color(0xFFD35400),
      styleInformation: BigTextStyleInformation(bigText, contentTitle: title),
    );
    const iosDetails = DarwinNotificationDetails();
    await _plugin.show(
      id: message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
      payload: 'route:$route',
    );
  }

  /// Rend une alerte (source ou sujet) à partir du `data` du push.
  ///
  /// Chemin de rendu UNIQUE, partagé par [showRemoteNotification] et les
  /// boutons QA : ceux-ci ne valent que s'ils empruntent exactement le même
  /// code qu'un vrai push. Le serveur duplique title/body dans `data`
  /// (cf. `_send_fcm` dans push_dispatcher.py), d'où la lecture prioritaire de
  /// `data` avec repli sur le bloc `notification` FCM.
  Future<void> _showAlert(
    Map<String, dynamic> data, {
    RemoteNotification? notification,
  }) async {
    final title = data['title'] as String? ?? notification?.title ?? '';
    final body = data['body'] as String? ?? notification?.body ?? '';
    final bigText = data['big_text'] as String? ?? body;
    final route = data['route'] as String? ?? '/digest';

    final androidDetails = AndroidNotificationDetails(
      // Canal NEUF et non une variante silencieuse de `digest_channel` :
      // Android fige son/importance à la création d'un canal et ignore toute
      // modification ultérieure sur un ID existant — le silence n'est
      // obtenable qu'avec un ID de canal jamais utilisé.
      'alerts_channel',
      'Alertes',
      channelDescription: 'Alertes des sources et sujets que tu suis.',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      playSound: false,
      enableVibration: false,
      icon: '@drawable/ic_stat_facteur',
      color: const Color(0xFFD35400),
      styleInformation: BigTextStyleInformation(bigText, contentTitle: title),
    );
    const iosDetails = DarwinNotificationDetails();

    await _plugin.show(
      // ID stable par cible (et non par message) : deux cibles différentes
      // cohabitent dans le tiroir, tandis qu'une seconde alerte de la MÊME
      // cible remplace la précédente au lieu de l'empiler.
      id: _NotifIds.sourceAlertBase +
          ((data['source_id'] ?? data['topic_id']) as String? ?? '')
                  .hashCode
                  .abs() %
              1000,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
      payload: 'route:$route',
    );
  }

  /// Injecte localement le payload EXACT qu'enverrait FCM pour une alerte
  /// source. Valide le canal silencieux, la copy, l'id de notification et le
  /// deep-link au tap. Ne valide PAS le transport FCM ni le producteur serveur.
  Future<void> showTestSourceAlert() async {
    const contentId = '00000000-0000-4000-8000-0000000000a1';
    const body = "Le pantouflage discret d'un ex-ministre";
    await _showAlert(const {
      'route': '/article/$contentId',
      'kind': 'source_alert',
      'source_id': '00000000-0000-4000-8000-0000000000b2',
      'source_name': 'Le Canard Enchaîné',
      'content_id': contentId,
      'channel': 'alerts',
      'big_text': '$body\nPublie environ une fois par mois',
      'title': 'Alerte : Le Canard Enchaîné vient de publier',
      'body': body,
    });
  }

  /// Pendant sujet du bouton QA ci-dessus — même canal, même rendu.
  Future<void> showTestTopicAlert() async {
    const contentId = '00000000-0000-4000-8000-0000000000a2';
    const body = 'La finale se jouera sans son meilleur buteur';
    await _showAlert(const {
      'route': '/article/$contentId',
      'kind': 'topic_alert',
      'topic_id': '00000000-0000-4000-8000-0000000000b3',
      'topic_name': 'Ligue 1',
      'content_id': contentId,
      'channel': 'alerts',
      'big_text': '$body\nPublie environ 2 fois par semaine',
      'title': 'Alerte : Ligue 1',
      'body': body,
    });
  }

  /// Décode `data['teasers']` (JSON liste de titres) de façon défensive :
  /// renvoie une liste vide si la charge est absente, mal formée, ou non-liste.
  static List<String> _parseTeasers(Object? raw) {
    if (raw is! String || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<String>()
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static void openRoute(String route) {
    final context = _navigatorKey?.currentContext;
    if (context == null) return;
    final tournee = ProviderScope.containerOf(context, listen: false)
        .read(tourneeProgressServiceProvider);
    // Navigation via GoRouter (et non le navigator impératif
    // `pushNamedAndRemoveUntil`, qui contournait le `redirect`) pour que le gate
    // Rituel s'applique : **toutes** les push (digest, bonnes nouvelles, article
    // hebdo…) passent par la lettre du jour tant qu'elle n'a pas été vue.
    final target = tournee.isMorningRitualShownTodaySync()
        ? route
        : RoutePaths.edition;
    GoRouter.of(context).go(target);
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

  /// Émetteur d'analytics au tap d'une notif locale — seam de test
  /// (réassignable), défaut = PostHog `notif_opened`.
  @visibleForTesting
  static void Function(String route) notifOpenedTracker = (route) => unawaited(
        PostHogService().capture(
          event: 'notif_opened',
          properties: {'type': 'local', 'route': route},
        ),
      );

  static void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    debugPrint(
      'PushNotificationService: tapped (id: ${response.id}, payload: $payload)',
    );

    final route = _routeFromPayload(payload);
    notifOpenedTracker(route);
    openRoute(route);
  }

  static String _routeFromPayload(String? payload) {
    if (payload == null || !payload.startsWith('route:')) {
      return '/flux-continu';
    }
    return payload.substring('route:'.length);
  }
}
