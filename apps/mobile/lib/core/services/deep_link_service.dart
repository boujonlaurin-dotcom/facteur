import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../config/routes.dart';
import 'analytics_service.dart';

/// Maps incoming `io.supabase.facteur://` URIs (typically widget taps) to
/// in-app GoRouter destinations.
///
/// Supported URIs:
/// - `io.supabase.facteur://digest` → `/digest`
/// - `io.supabase.facteur://digest/<contentId>?pos=<n>&topicId=<id>`
///   → `/flux-continu/content/<contentId>` (article reader, Essentiel deep link)
/// - `io.supabase.facteur://feed` → `/flaner`
/// - `io.supabase.facteur://feed/content/<contentId>?pos=<n>&topicId=<id>`
///   → `/flaner/content/<contentId>` (article reader, Flâner deep link)
/// - `io.supabase.facteur://veille/dashboard` → `/veille/dashboard`
/// - `io.supabase.facteur://grille` → `/grille` (« Le mot du jour », partagé
///   entre amis — ouvre la grille dans l'app au lieu du site facteur.app)
/// - `io.supabase.facteur://login-callback#...` → auth callback, routed by the
///   auth state listener. Password recovery opens `/reset-password`.
class DeepLinkService {
  DeepLinkService._({AppLinks? appLinks, AnalyticsService? analytics})
      : _appLinks = appLinks ?? AppLinks(),
        _analytics = analytics;

  /// Test-only factory letting suites inject a fake AppLinks/Analytics.
  @visibleForTesting
  factory DeepLinkService.forTest({
    AppLinks? appLinks,
    AnalyticsService? analytics,
  }) {
    return DeepLinkService._(appLinks: appLinks, analytics: analytics);
  }

  static DeepLinkService? _instance;

  static DeepLinkService get instance {
    return _instance ??= DeepLinkService._();
  }

  /// Visible for tests.
  @visibleForTesting
  static void setInstanceForTest(DeepLinkService service) {
    _instance = service;
  }

  /// Visible for tests.
  @visibleForTesting
  static void resetForTest() {
    _instance?.dispose();
    _instance = null;
  }

  final AppLinks _appLinks;
  AnalyticsService? _analytics;
  StreamSubscription<Uri>? _sub;

  /// URI captured before the router was ready or before the user authenticated.
  /// Replayed once both conditions are met via [flushPendingIfReady].
  Uri? _pending;

  /// `true` once a cold-start link has been seeded via [seedPending] (from
  /// `main.dart`). Lets [start] skip its own `getInitialLink` so the link isn't
  /// handled twice (which would double-navigate after the redirect consumed it).
  bool _initialLinkSeeded = false;

  /// Reference to the current [GoRouter]. Set via [bind] from `app.dart`.
  GoRouter? _router;

  /// Tells the service whether the user is currently authenticated. Updated
  /// from `app.dart` via a Riverpod listener on `authStateProvider`.
  bool _authenticated = false;

  /// Callback invoked when a widget tap explicitly requests a feed refresh
  /// (`io.supabase.facteur://feed?refresh=1`, fired by the widget's refresh
  /// button). Wired from `app.dart` to `feedProvider.refresh()`.
  VoidCallback? _onRefreshRequested;

  /// Bind the service to the running router and analytics. Idempotent.
  void bind({
    required GoRouter router,
    AnalyticsService? analytics,
    VoidCallback? onRefreshRequested,
  }) {
    _router = router;
    if (analytics != null) {
      _analytics = analytics;
    }
    if (onRefreshRequested != null) {
      _onRefreshRequested = onRefreshRequested;
    }
  }

  /// Tell the service that the user is authenticated. Call from app.dart on
  /// auth state change. Triggers a replay of any pending URI.
  void setAuthenticated(bool value) {
    final wasAuthed = _authenticated;
    _authenticated = value;
    if (!wasAuthed && value) {
      flushPendingIfReady();
    }
  }

  /// Start listening for incoming links. Safe to call multiple times.
  Future<void> start() async {
    if (_sub != null) return;

    // 1. Cold start: check the URI that launched the app — unless main.dart
    // already seeded it via [seedPending] (then the redirect owns it).
    if (!_initialLinkSeeded) {
      try {
        final initial = await _appLinks.getInitialLink();
        if (initial != null) {
          _handle(initial);
        }
      } catch (e) {
        debugPrint('DeepLinkService: getInitialLink failed: $e');
      }
    }

    // 2. Hot stream: subsequent URIs while the app is alive.
    _sub = _appLinks.uriLinkStream.listen(
      _handle,
      onError: (Object e) {
        debugPrint('DeepLinkService: uriLinkStream error: $e');
      },
    );
  }

  /// Handle one incoming URI. Public for tests.
  @visibleForTesting
  void handle(Uri uri) => _handle(uri);

  void _handle(Uri uri) {
    debugPrint('DeepLinkService: incoming uri=$uri');

    if (uri.scheme != 'io.supabase.facteur') {
      return;
    }

    final action = parse(uri);
    if (action.target == WidgetDeepLinkTarget.authCallback) {
      _route(uri);
      return;
    }

    // Auth gate: if not authenticated yet, hold the URI and replay later.
    if (!_authenticated) {
      _pending = uri;
      return;
    }

    _route(uri);
  }

  /// Replay the pending URI if both router is bound and user is authenticated.
  void flushPendingIfReady() {
    final pending = _pending;
    if (pending == null) return;
    if (!_authenticated) return;
    if (_router == null) return;
    _pending = null;
    _route(pending);
  }

  /// Seed a pending URI without going through the auth gate. Used at boot from
  /// `main.dart` (`AppLinks().getInitialLink()`) so the cold-start deep link is
  /// known *before* the first GoRouter redirect resolves — making the deep link
  /// the single source of truth for the post-auth landing route instead of
  /// racing [flushPendingIfReady] against `postAuthHomePath()`.
  void seedPending(Uri uri) {
    if (uri.scheme != 'io.supabase.facteur') return;
    _pending = uri;
    _initialLinkSeeded = true;
  }

  /// Resolve the in-app route for the currently pending URI **without
  /// consuming it**, or `null` when nothing navigable is pending. Called by the
  /// router `redirect` to land cold-opens on their deep-linked destination.
  String? pendingRoute() {
    final pending = _pending;
    if (pending == null) return null;
    final action = parse(pending);
    switch (action.target) {
      case WidgetDeepLinkTarget.article:
      case WidgetDeepLinkTarget.digest:
      case WidgetDeepLinkTarget.feed:
      case WidgetDeepLinkTarget.veille:
      case WidgetDeepLinkTarget.grille:
        return action.route;
      case WidgetDeepLinkTarget.authCallback:
      case WidgetDeepLinkTarget.ignored:
      case WidgetDeepLinkTarget.unhandled:
        return null;
    }
  }

  /// Clear the pending URI. Called by the redirect once it has consumed the
  /// pending route via [pendingRoute] so [flushPendingIfReady] becomes a no-op
  /// (no double navigation on cold-open).
  void clearPending() {
    _pending = null;
  }

  void _route(Uri uri) {
    final router = _router;
    if (router == null) {
      _pending = uri;
      return;
    }

    final action = parse(uri);
    switch (action.target) {
      case WidgetDeepLinkTarget.article:
        _analytics?.trackWidgetAppOpened(
          target: 'article',
          articleId: action.articleId,
          position: action.position,
          topicId: action.topicId,
        );
        _analytics?.trackWidgetArticleOpened(
          articleId: action.articleId!,
          position: action.position,
          topicId: action.topicId,
        );
        router.go(action.route!);
        return;
      case WidgetDeepLinkTarget.digest:
        _analytics?.trackWidgetAppOpened(target: 'digest');
        router.go(action.route!);
        return;
      case WidgetDeepLinkTarget.feed:
        _analytics?.trackWidgetAppOpened(target: 'feed');
        router.go(action.route!);
        // Widget refresh button: after landing on Flâner, force a feed refresh
        // (which re-pushes the widget through the existing path).
        if (action.refresh) {
          _onRefreshRequested?.call();
        }
        return;
      case WidgetDeepLinkTarget.veille:
        _analytics?.trackWidgetAppOpened(target: 'veille');
        router.go(action.route!);
        return;
      case WidgetDeepLinkTarget.grille:
        _analytics?.trackWidgetAppOpened(target: 'grille');
        router.go(action.route!);
        return;
      case WidgetDeepLinkTarget.authCallback:
        router.go(action.route ?? RoutePaths.splash);
        return;
      case WidgetDeepLinkTarget.ignored:
      case WidgetDeepLinkTarget.unhandled:
        debugPrint('DeepLinkService: unhandled uri=$uri');
        return;
    }
  }

  /// Pure-function parser. Used by `_route` and exposed for tests.
  ///
  /// Recognises both `host=digest` and `host="" + first path segment=digest`
  /// because Android's URI parsing varies depending on intent shape.
  static WidgetDeepLinkAction parse(Uri uri) {
    if (uri.host == 'login-callback' ||
        uri.path.startsWith('/login-callback')) {
      final authType = _authCallbackType(uri);
      return WidgetDeepLinkAction(
        target: WidgetDeepLinkTarget.authCallback,
        route: authType == 'recovery'
            ? RoutePaths.resetPassword
            : RoutePaths.splash,
        authType: authType,
      );
    }
    if (uri.scheme != 'io.supabase.facteur') {
      return const WidgetDeepLinkAction(target: WidgetDeepLinkTarget.unhandled);
    }

    final host = uri.host;
    final segments = uri.pathSegments;

    final isDigest = host == 'digest' ||
        (host.isEmpty && segments.isNotEmpty && segments.first == 'digest');
    final isFeed = host == 'feed' ||
        (host.isEmpty && segments.isNotEmpty && segments.first == 'feed');
    final isVeille = host == 'veille' ||
        (host.isEmpty && segments.isNotEmpty && segments.first == 'veille');
    final isGrille = host == 'grille' ||
        (host.isEmpty && segments.isNotEmpty && segments.first == 'grille');

    if (isGrille) {
      // « Le mot du jour » partagé entre amis : ouvre la grille dans l'app.
      return const WidgetDeepLinkAction(
        target: WidgetDeepLinkTarget.grille,
        route: RoutePaths.grille,
      );
    }

    if (isVeille) {
      // La veille n'a plus d'écran dédié — son contenu vit dans la Tournée
      // du jour (slot kind=veille). Les anciens deep links widget
      // `io.supabase.facteur://veille/dashboard` sont redirigés vers le
      // flux continu, où la section veille apparaît avec son accent dédié.
      return const WidgetDeepLinkAction(
        target: WidgetDeepLinkTarget.veille,
        route: RoutePaths.fluxContinu,
      );
    }

    if (isDigest) {
      final articleId = _extractArticleIdFrom(host, segments);
      if (articleId != null && articleId.isNotEmpty) {
        return WidgetDeepLinkAction(
          target: WidgetDeepLinkTarget.article,
          route: '/flux-continu/content/$articleId',
          articleId: articleId,
          position: int.tryParse(uri.queryParameters['pos'] ?? ''),
          topicId: uri.queryParameters['topicId'],
        );
      }
      // Le digest a fusionné dans la Tournée du jour lors du cleanup
      // post-unification — on redirige vers le flux continu.
      return const WidgetDeepLinkAction(
        target: WidgetDeepLinkTarget.digest,
        route: RoutePaths.fluxContinu,
      );
    }
    if (isFeed) {
      // Flux article: `io.supabase.facteur://feed/content/<id>` — emitted by
      // the Kotlin RemoteViewsFactory in Flux mode. host="feed" gives segments
      // `[content, <id>]`; some Android intent shapes deliver host="" with
      // segments `[feed, content, <id>]`, so we normalise both.
      final feedSegments =
          host == 'feed' ? segments : segments.skip(1).toList();
      if (feedSegments.length >= 2 && feedSegments[0] == 'content') {
        final articleId = feedSegments[1];
        if (articleId.isNotEmpty) {
          return WidgetDeepLinkAction(
            target: WidgetDeepLinkTarget.article,
            route: '${RoutePaths.flaner}/content/$articleId',
            articleId: articleId,
            position: int.tryParse(uri.queryParameters['pos'] ?? ''),
            topicId: uri.queryParameters['topicId'],
          );
        }
      }
      // FeedScreen historique — on route vers Flâner, désormais page feed
      // autonome. `refresh=1` (bouton refresh du widget) garde la route Flâner
      // mais signale qu'un rafraîchissement du flux doit suivre.
      return WidgetDeepLinkAction(
        target: WidgetDeepLinkTarget.feed,
        route: RoutePaths.flaner,
        refresh: uri.queryParameters['refresh'] == '1',
      );
    }

    return const WidgetDeepLinkAction(target: WidgetDeepLinkTarget.unhandled);
  }

  static String? _authCallbackType(Uri uri) {
    final fromQuery = uri.queryParameters['type'];
    if (fromQuery != null && fromQuery.isNotEmpty) return fromQuery;
    if (uri.fragment.isEmpty) return null;
    return Uri.splitQueryString(uri.fragment)['type'];
  }

  static String? _extractArticleIdFrom(String host, List<String> segments) {
    if (host == 'digest') {
      if (segments.isNotEmpty) return segments.first;
      return null;
    }
    if (host.isEmpty && segments.isNotEmpty && segments.first == 'digest') {
      if (segments.length >= 2) return segments[1];
    }
    return null;
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _router = null;
    _pending = null;
    _onRefreshRequested = null;
    _initialLinkSeeded = false;
  }
}

enum WidgetDeepLinkTarget {
  digest,
  article,
  feed,
  veille,
  grille,
  authCallback,
  ignored,
  unhandled,
}

class WidgetDeepLinkAction {
  final WidgetDeepLinkTarget target;
  final String? route;
  final String? articleId;
  final int? position;
  final String? topicId;
  final String? authType;

  /// `true` when the link carries `refresh=1` (widget refresh button) — the
  /// router lands on Flâner and the service then triggers a feed refresh.
  final bool refresh;

  const WidgetDeepLinkAction({
    required this.target,
    this.route,
    this.articleId,
    this.position,
    this.topicId,
    this.authType,
    this.refresh = false,
  });
}
