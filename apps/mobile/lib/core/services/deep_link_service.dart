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
///
/// `io.supabase.facteur://login-callback` is intentionally ignored — Supabase
/// SDK intercepts it before it reaches us. Anything else falls through to
/// GoRouter's `errorBuilder`, which is a safety net only.
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

  /// Reference to the current [GoRouter]. Set via [bind] from `app.dart`.
  GoRouter? _router;

  /// Tells the service whether the user is currently authenticated. Updated
  /// from `app.dart` via a Riverpod listener on `authStateProvider`.
  bool _authenticated = false;

  /// Bind the service to the running router and analytics. Idempotent.
  void bind({required GoRouter router, AnalyticsService? analytics}) {
    _router = router;
    if (analytics != null) {
      _analytics = analytics;
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

    // 1. Cold start: check the URI that launched the app.
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        _handle(initial);
      }
    } catch (e) {
      debugPrint('DeepLinkService: getInitialLink failed: $e');
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

    // Supabase OAuth/email confirmation — let the SDK handle it.
    if (uri.host == 'login-callback' ||
        uri.path.startsWith('/login-callback')) {
      return;
    }

    if (uri.scheme != 'io.supabase.facteur') {
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
        return;
      case WidgetDeepLinkTarget.veille:
        _analytics?.trackWidgetAppOpened(target: 'veille');
        router.go(action.route!);
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
      return const WidgetDeepLinkAction(target: WidgetDeepLinkTarget.ignored);
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
      // autonome.
      return const WidgetDeepLinkAction(
        target: WidgetDeepLinkTarget.feed,
        route: RoutePaths.flaner,
      );
    }

    return const WidgetDeepLinkAction(target: WidgetDeepLinkTarget.unhandled);
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
  }
}

enum WidgetDeepLinkTarget { digest, article, feed, veille, ignored, unhandled }

class WidgetDeepLinkAction {
  final WidgetDeepLinkTarget target;
  final String? route;
  final String? articleId;
  final int? position;
  final String? topicId;

  const WidgetDeepLinkAction({
    required this.target,
    this.route,
    this.articleId,
    this.position,
    this.topicId,
  });
}
