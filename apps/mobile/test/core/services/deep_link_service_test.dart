import 'package:facteur/core/services/deep_link_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  group('DeepLinkService.parse', () {
    test('digest host without article → digest target', () {
      final action = DeepLinkService.parse(
        Uri.parse('io.supabase.facteur://digest'),
      );
      expect(action.target, WidgetDeepLinkTarget.digest);
      expect(action.route, '/flux-continu');
      expect(action.articleId, isNull);
    });

    test('digest with trailing slash (no article) → digest target', () {
      final action = DeepLinkService.parse(
        Uri.parse('io.supabase.facteur://digest/'),
      );
      expect(action.target, WidgetDeepLinkTarget.digest);
      expect(action.route, '/flux-continu');
    });

    test('digest host with article id → article reader route', () {
      final action = DeepLinkService.parse(
        Uri.parse(
          'io.supabase.facteur://digest/abc-123?pos=2&topicId=international',
        ),
      );
      expect(action.target, WidgetDeepLinkTarget.article);
      expect(action.route, '/flux-continu/content/abc-123');
      expect(action.articleId, 'abc-123');
      expect(action.position, 2);
      expect(action.topicId, 'international');
    });

    test('veille/dashboard (legacy widget link) → flux continu', () {
      final action = DeepLinkService.parse(
        Uri.parse('io.supabase.facteur://veille/dashboard'),
      );
      expect(action.target, WidgetDeepLinkTarget.veille);
      expect(action.route, '/flux-continu');
    });

    test('veille bare host → flux continu', () {
      final action = DeepLinkService.parse(
        Uri.parse('io.supabase.facteur://veille'),
      );
      expect(action.target, WidgetDeepLinkTarget.veille);
      expect(action.route, '/flux-continu');
    });

    test('feed host → flâner (FeedScreen supprimé)', () {
      final action = DeepLinkService.parse(
        Uri.parse('io.supabase.facteur://feed'),
      );
      expect(action.target, WidgetDeepLinkTarget.feed);
      expect(action.route, '/flaner');
    });

    test('feed/content/<id> → article reader (Flâner deep link)', () {
      final action = DeepLinkService.parse(
        Uri.parse(
          'io.supabase.facteur://feed/content/abc-123?pos=4&topicId=tech',
        ),
      );
      expect(action.target, WidgetDeepLinkTarget.article);
      expect(action.route, '/flaner/content/abc-123');
      expect(action.articleId, 'abc-123');
      expect(action.position, 4);
      expect(action.topicId, 'tech');
    });

    test('feed/content/<id> with empty host → article reader', () {
      // Some Android intent shapes drop the host and prepend it as a path
      // segment instead. Both shapes should resolve to the article reader.
      final action = DeepLinkService.parse(
        Uri.parse('io.supabase.facteur:///feed/content/abc-123?pos=7'),
      );
      expect(action.target, WidgetDeepLinkTarget.article);
      expect(action.route, '/flaner/content/abc-123');
      expect(action.articleId, 'abc-123');
      expect(action.position, 7);
    });

    test('feed/content/ (id missing) falls back to flâner', () {
      final action = DeepLinkService.parse(
        Uri.parse('io.supabase.facteur://feed/content/'),
      );
      expect(action.target, WidgetDeepLinkTarget.feed);
      expect(action.route, '/flaner');
    });

    test('grille host → /grille (mot du jour partagé entre amis)', () {
      final action = DeepLinkService.parse(
        Uri.parse('io.supabase.facteur://grille'),
      );
      expect(action.target, WidgetDeepLinkTarget.grille);
      expect(action.route, '/grille');
    });

    test('grille bare path (host vide) → /grille', () {
      final action = DeepLinkService.parse(
        Uri.parse('io.supabase.facteur:///grille'),
      );
      expect(action.target, WidgetDeepLinkTarget.grille);
      expect(action.route, '/grille');
    });

    test('login-callback URI is identified as an auth callback', () {
      final action = DeepLinkService.parse(
        Uri.parse('io.supabase.facteur://login-callback#access_token=xyz'),
      );
      expect(action.target, WidgetDeepLinkTarget.authCallback);
      expect(action.route, '/splash');
      expect(action.authType, isNull);
    });

    test('login-callback recovery URI routes to reset password', () {
      final action = DeepLinkService.parse(
        Uri.parse(
          'io.supabase.facteur://login-callback#access_token=xyz&type=recovery',
        ),
      );
      expect(action.target, WidgetDeepLinkTarget.authCallback);
      expect(action.route, '/reset-password');
      expect(action.authType, 'recovery');
    });

    test('login-callback query recovery also routes to reset password', () {
      final action = DeepLinkService.parse(
        Uri.parse(
          'io.supabase.facteur://login-callback?code=abc&type=recovery',
        ),
      );
      expect(action.target, WidgetDeepLinkTarget.authCallback);
      expect(action.route, '/reset-password');
      expect(action.authType, 'recovery');
    });

    test('foreign scheme → unhandled', () {
      final action = DeepLinkService.parse(
        Uri.parse('https://facteur.app/digest'),
      );
      expect(action.target, WidgetDeepLinkTarget.unhandled);
    });

    test('unknown host on facteur scheme → unhandled', () {
      final action = DeepLinkService.parse(
        Uri.parse('io.supabase.facteur://unknown-target'),
      );
      expect(action.target, WidgetDeepLinkTarget.unhandled);
    });

    test('article id with empty pos query falls back to null position', () {
      final action = DeepLinkService.parse(
        Uri.parse('io.supabase.facteur://digest/abc?pos='),
      );
      expect(action.target, WidgetDeepLinkTarget.article);
      expect(action.position, isNull);
    });

    test('feed?refresh=1 → flâner + refresh flag (bouton refresh widget)', () {
      final action = DeepLinkService.parse(
        Uri.parse('io.supabase.facteur://feed?refresh=1'),
      );
      expect(action.target, WidgetDeepLinkTarget.feed);
      expect(action.route, '/flaner');
      expect(action.refresh, isTrue);
    });

    test('feed sans refresh → flag refresh false', () {
      final action = DeepLinkService.parse(
        Uri.parse('io.supabase.facteur://feed'),
      );
      expect(action.target, WidgetDeepLinkTarget.feed);
      expect(action.refresh, isFalse);
    });
  });

  group('DeepLinkService pending (cold-start seed)', () {
    tearDown(DeepLinkService.resetForTest);

    test('seedPending + pendingRoute resolves the route without consuming', () {
      final service = DeepLinkService.forTest();
      DeepLinkService.setInstanceForTest(service);

      service.seedPending(
        Uri.parse('io.supabase.facteur://feed/content/abc-123'),
      );

      // Resolves but does not consume — repeatable.
      expect(service.pendingRoute(), '/flaner/content/abc-123');
      expect(service.pendingRoute(), '/flaner/content/abc-123');
    });

    test('clearPending makes pendingRoute null', () {
      final service = DeepLinkService.forTest();
      DeepLinkService.setInstanceForTest(service);

      service.seedPending(Uri.parse('io.supabase.facteur://digest/xyz'));
      expect(service.pendingRoute(), '/flux-continu/content/xyz');

      service.clearPending();
      expect(service.pendingRoute(), isNull);
    });

    test('seedPending ignores foreign schemes', () {
      final service = DeepLinkService.forTest();
      DeepLinkService.setInstanceForTest(service);

      service.seedPending(Uri.parse('https://facteur.app/digest'));
      expect(service.pendingRoute(), isNull);
    });

    test('pendingRoute is null for non-navigable (auth callback) links', () {
      final service = DeepLinkService.forTest();
      DeepLinkService.setInstanceForTest(service);

      service.seedPending(
        Uri.parse('io.supabase.facteur://login-callback#access_token=xyz'),
      );
      expect(service.pendingRoute(), isNull);
    });

    // Régression C4 : au cold start, le routeur consommait `pendingRoute()` et
    // jetait `action.refresh`. `_onRefreshRequested` n'était jamais appelé →
    // le bouton refresh du widget était un no-op littéral quand l'app était
    // tuée. Cf. docs/bugs/bug-widget-fiabilite.md.
    test('pendingAction carries the refresh flag through a cold start', () {
      final service = DeepLinkService.forTest();
      DeepLinkService.setInstanceForTest(service);

      service.seedPending(Uri.parse('io.supabase.facteur://feed?refresh=1'));

      final action = service.pendingAction();
      expect(action, isNotNull);
      expect(action!.refresh, isTrue);
      expect(DeepLinkService.navigableRouteFor(action), '/flaner');
    });

    test('pendingAction has refresh=false on a plain feed link', () {
      final service = DeepLinkService.forTest();
      DeepLinkService.setInstanceForTest(service);

      service.seedPending(Uri.parse('io.supabase.facteur://feed'));
      expect(service.pendingAction()!.refresh, isFalse);
    });

    test('replayRefreshIfRequested fires the callback only when refresh=1',
        () {
      var calls = 0;
      final service = DeepLinkService.forTest();
      DeepLinkService.setInstanceForTest(service);
      service.bind(
        router: GoRouter(routes: [
          GoRoute(path: '/', builder: (_, __) => const SizedBox.shrink()),
        ]),
        onRefreshRequested: () => calls++,
      );

      service.replayRefreshIfRequested(
        DeepLinkService.parse(Uri.parse('io.supabase.facteur://feed')),
      );
      expect(calls, 0);

      service.replayRefreshIfRequested(
        DeepLinkService.parse(
          Uri.parse('io.supabase.facteur://feed?refresh=1'),
        ),
      );
      expect(calls, 1);
    });
  });

  // Regression: a widget article tap must open the reader by STACKING (push),
  // not replacing (go), so it works even when a reader is already on screen —
  // letting the user chain article reads from the home-screen widget.
  group('DeepLinkService article navigation (widget tap → reader stacks)', () {
    tearDown(DeepLinkService.resetForTest);

    // Minimal router mirroring the two reader paths the widget deep links
    // resolve to (`/flaner/content/:id`, `/flux-continu/content/:id`). The
    // placeholder reader just renders its id so we can assert what's on top.
    GoRouter buildRouter(GlobalKey<NavigatorState> navKey) {
      Widget reader(BuildContext c, GoRouterState s) =>
          Scaffold(body: Text('reader-${s.pathParameters['id']}'));
      return GoRouter(
        navigatorKey: navKey,
        initialLocation: '/flaner',
        routes: [
          GoRoute(
            path: '/flaner',
            builder: (c, s) => const Scaffold(body: Text('flaner-home')),
          ),
          GoRoute(path: '/flaner/content/:id', builder: reader),
          GoRoute(
            path: '/flux-continu',
            builder: (c, s) => const Scaffold(body: Text('flux-home')),
          ),
          GoRoute(path: '/flux-continu/content/:id', builder: reader),
        ],
      );
    }

    Future<DeepLinkService> boundService(
      WidgetTester tester,
      GlobalKey<NavigatorState> navKey,
    ) async {
      final router = buildRouter(navKey);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      final service = DeepLinkService.forTest();
      DeepLinkService.setInstanceForTest(service);
      service.bind(router: router);
      service.setAuthenticated(true);
      return service;
    }

    testWidgets(
      'Flux article: tapping a 2nd widget article while already in a reader '
      'stacks a new reader (chaining), not a no-op / replace',
      (tester) async {
        final navKey = GlobalKey<NavigatorState>();
        final service = await boundService(tester, navKey);

        // First tap → user is now "in an article".
        service.handle(Uri.parse('io.supabase.facteur://feed/content/first'));
        await tester.pumpAndSettle();
        expect(find.text('reader-first'), findsOneWidget);

        // Second tap WHILE inside the reader → opens the second article on top.
        service.handle(Uri.parse('io.supabase.facteur://feed/content/second'));
        await tester.pumpAndSettle();
        expect(find.text('reader-second'), findsOneWidget);

        // Proof it STACKED: popping the top reveals the first article. Under the
        // old `go` (replace) there would be no first reader to pop back to.
        navKey.currentState!.pop();
        await tester.pumpAndSettle();
        expect(find.text('reader-first'), findsOneWidget);
      },
    );

    testWidgets(
      'Essentiel (digest) article stacks a reader the same way',
      (tester) async {
        final navKey = GlobalKey<NavigatorState>();
        final service = await boundService(tester, navKey);

        service.handle(Uri.parse('io.supabase.facteur://digest/aaa'));
        await tester.pumpAndSettle();
        expect(find.text('reader-aaa'), findsOneWidget);

        service.handle(Uri.parse('io.supabase.facteur://digest/bbb'));
        await tester.pumpAndSettle();
        expect(find.text('reader-bbb'), findsOneWidget);

        navKey.currentState!.pop();
        await tester.pumpAndSettle();
        expect(find.text('reader-aaa'), findsOneWidget);
      },
    );

    testWidgets(
      'from the home tab (no reader open) a widget article still opens the '
      'reader',
      (tester) async {
        final navKey = GlobalKey<NavigatorState>();
        final service = await boundService(tester, navKey);
        expect(find.text('flaner-home'), findsOneWidget);

        service.handle(Uri.parse('io.supabase.facteur://feed/content/solo'));
        await tester.pumpAndSettle();
        expect(find.text('reader-solo'), findsOneWidget);
      },
    );
  });
}
