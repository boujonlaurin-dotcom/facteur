import '../../config/routes.dart';
import '../../features/flux_continu/providers/selected_edition_date_provider.dart';

/// Intention de navigation dérivée — de façon **pure** — d'un tap de
/// notification, quelle que soit sa provenance (données FCM d'un push serveur
/// ou payload `route:` d'une notif locale).
///
/// Trois symptômes historiques au tap d'une notif un peu ancienne, une cause
/// commune : le tap routait toujours vers l'Essentiel *vivant du jour* en
/// jetant la date (`target_date`, pourtant envoyée par le backend) et le filtre
/// de section. Ce parseur les restitue :
///
/// - **édition** (`#1`/`#3`) : `target_date` → [EditionToday] si == jour
///   d'édition courant (frontière 7h30 via [editionTodayDate]), sinon
///   [EditionPastDay] (lettre figée côté backend, ce qui préserve aussi les
///   articles teasés) ;
/// - **section** (`#2`) : `section='bonnes'` → scroll vers la section Bonnes
///   Nouvelles (consommé par `flux_continu_screen` via
///   `pendingFeedSectionKeyProvider`).
///
/// Le digest est **data-only sur Android** (notif rendue par nous → tap via le
/// pipeline local) et *notification-type* sur iOS (tap via FCM). Les deux
/// pipelines convergent ici, puis vers l'applier
/// `PushNotificationService.routeIntent`. C'est aussi ce fichier qui **écrit**
/// le payload local ([encodeLocalPayload]), pour que l'encodeur et le décodeur
/// de la convention ne puissent pas diverger.
///
/// Aucune dépendance widget : testable en unitaire pur.
class NotificationIntent {
  /// Édition à afficher dans le bloc Essentiel (feed vivant vs. lettre figée).
  final EditionSelection edition;

  /// Clé de section à révéler par scroll (`'bonnes'`, …), ou `null` pour une
  /// ouverture normale (feed en haut). **Toujours** portée explicitement à
  /// l'application (un `null` purge une clé restée d'un tap précédent).
  final String? section;

  /// Route GoRouter cible. Le legacy `/digest` est réécrit en `/flux-continu`
  /// (le digest a fusionné dans la Tournée) ; les autres routes (article,
  /// veille…) passent inchangées.
  final String navigationPath;

  const NotificationIntent({
    required this.edition,
    required this.section,
    required this.navigationPath,
  });

  /// Préfixe du payload des notifs locales (`flutter_local_notifications`).
  static const String _payloadPrefix = 'route:';

  /// Clés de routing reportées du `data` FCM vers le payload local, pour que le
  /// tap Android reconstruise la même intention que le tap iOS.
  static const List<String> _routingKeys = ['target_date', 'section'];

  /// `true` si la cible est le feed — seul cas où poser un état d'édition / de
  /// section a un sens. Pour une alerte article ou l'onboarding, écrire ces
  /// providers figerait l'Essentiel sur une édition passée en sortant de
  /// l'article ; l'applier s'en sert pour ne pas pouvoir le faire.
  bool get targetsFeed => navigationPath == RoutePaths.fluxContinu;

  /// Parse depuis les `data` d'un push FCM (chemin iOS, et source de vérité de
  /// `target_date`, envoyée par `push_composer.compose_daily_digest`).
  static NotificationIntent parseFromFcmData(
    Map<String, dynamic> data, {
    DateTime? now,
  }) =>
      _from(
        path: _asString(data['route']) ?? RoutePaths.fluxContinu,
        targetDate: _asString(data['target_date']),
        section: _asString(data['section']),
        now: now,
      );

  /// Parse depuis le payload d'une notif locale (`route:<url>`, chemin Android).
  /// L'URL porte les clés de [_routingKeys] écrites par [encodeLocalPayload].
  static NotificationIntent parseFromLocalPayload(
    String? payload, {
    DateTime? now,
  }) {
    final uri = Uri.tryParse(rawRouteFromPayload(payload)) ??
        Uri(path: RoutePaths.fluxContinu);
    return _from(
      path: uri.path.isEmpty ? RoutePaths.fluxContinu : uri.path,
      targetDate: uri.queryParameters['target_date'],
      section: uri.queryParameters['section'],
      now: now,
    );
  }

  /// Route brute d'un payload local (`route:<url>`), défaut `/flux-continu`.
  /// Propriétaire unique de la convention `route:` — utilisé aussi pour
  /// l'analytics, qui veut la route *avec* sa query (plus discriminante).
  static String rawRouteFromPayload(String? payload) =>
      (payload != null && payload.startsWith(_payloadPrefix))
          ? payload.substring(_payloadPrefix.length)
          : RoutePaths.fluxContinu;

  /// Construit le payload d'une notif locale à partir de la [route] et du `data`
  /// du push serveur. Sans ça, une notif rendue localement (Android) perdait les
  /// clés de routing que le même push conserve en FCM (iOS).
  static String encodeLocalPayload(String route, Map<String, dynamic> data) {
    final extras = <String>[
      for (final key in _routingKeys)
        if ((_asString(data[key]) ?? '').trim().isNotEmpty)
          '$key=${_asString(data[key])!.trim()}',
    ];
    if (extras.isEmpty) return '$_payloadPrefix$route';
    final sep = route.contains('?') ? '&' : '?';
    return '$_payloadPrefix$route$sep${extras.join('&')}';
  }

  static NotificationIntent _from({
    required String path,
    required String? targetDate,
    required String? section,
    DateTime? now,
  }) =>
      NotificationIntent(
        edition: _editionFromTargetDate(targetDate, now: now),
        section: _cleanSection(section),
        // `/digest` (legacy) → `/flux-continu` : rend `navigationPath`
        // déterministe et testable sans monter le router.
        navigationPath:
            path == RoutePaths.digest ? RoutePaths.fluxContinu : path,
      );

  static String? _asString(Object? value) => value is String ? value : null;

  static String? _cleanSection(String? raw) {
    final trimmed = raw?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  /// Mappe `target_date` (ISO `YYYY-MM-DD`) sur l'édition à ouvrir : le jour
  /// d'édition courant (frontière 7h30 via [editionTodayDate]) → [EditionToday]
  /// (feed vivant) ; un jour antérieur → [EditionPastDay] (lettre figée).
  /// Absent / illisible / futur → [EditionToday] (dégradé sûr, jamais un
  /// plantage).
  static EditionSelection _editionFromTargetDate(String? raw, {DateTime? now}) {
    if (raw == null || raw.isEmpty) return const EditionToday();
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return const EditionToday();
    // Date-nue locale : l'égalité d'édition se joue au jour calendaire.
    final target = DateTime(parsed.year, parsed.month, parsed.day);
    final today = editionTodayDate(now: now);
    if (!target.isBefore(today)) return const EditionToday();
    return EditionPastDay(target);
  }

  @override
  bool operator ==(Object other) =>
      other is NotificationIntent &&
      other.edition == edition &&
      other.section == section &&
      other.navigationPath == navigationPath;

  @override
  int get hashCode => Object.hash(edition, section, navigationPath);

  @override
  String toString() => 'NotificationIntent(edition: ${edition.key}, '
      'section: $section, navigationPath: $navigationPath)';
}
