import 'package:facteur/core/services/notification_intent.dart';
import 'package:facteur/core/services/push_notification_service.dart';
import 'package:facteur/features/flux_continu/providers/pending_feed_section_provider.dart';
import 'package:facteur/features/flux_continu/providers/selected_edition_date_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Valide l'applier `PushNotificationService.routeIntent` : il pose l'état
/// d'édition + de section via le container Riverpod (récupéré depuis le
/// contexte du navigator racine) PUIS navigue. On ne monte pas le lourd
/// `FluxContinuScreen` (il consomme ces mêmes providers, mécanique déjà
/// couverte) — on vérifie ici uniquement que l'état est correctement posé.
void main() {
  // 10:00 Paris le 2026-08-08 → édition « aujourd'hui » = 2026-08-08.
  final now = DateTime.utc(2026, 8, 8, 8);

  Future<ProviderContainer> pumpHarness(WidgetTester tester) async {
    final navKey = GlobalKey<NavigatorState>();
    final router = GoRouter(
      navigatorKey: navKey,
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const Text('home')),
        GoRoute(
          path: '/flux-continu',
          builder: (_, __) => const Text('flux'),
          routes: [
            GoRoute(
              path: 'content/:id',
              builder: (_, __) => const Text('article'),
            ),
          ],
        ),
      ],
    );
    PushNotificationService.setNavigatorKey(navKey);
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(navKey.currentContext!);
  }

  testWidgets('bonnes nouvelles : pose section=bonnes + EditionToday + navigue',
      (tester) async {
    final container = await pumpHarness(tester);

    PushNotificationService.routeIntent(
      NotificationIntent.parseFromLocalPayload(
        'route:/flux-continu?section=bonnes',
        now: now,
      ),
    );
    await tester.pumpAndSettle();

    expect(container.read(pendingFeedSectionKeyProvider), 'bonnes');
    expect(container.read(selectedEditionDateProvider), const EditionToday());
    expect(find.text('flux'), findsOneWidget);
  });

  testWidgets('digest de la veille : pose EditionPastDay figée, section nulle',
      (tester) async {
    final container = await pumpHarness(tester);

    PushNotificationService.routeIntent(
      NotificationIntent.parseFromFcmData(
        {'route': '/digest', 'target_date': '2026-08-07'},
        now: now,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      container.read(selectedEditionDateProvider),
      EditionPastDay(DateTime(2026, 8, 7)),
    );
    expect(container.read(pendingFeedSectionKeyProvider), isNull);
    expect(find.text('flux'), findsOneWidget);
  });

  testWidgets(
      'section toujours explicite : un intent sans section purge une '
      'clé pending restée d\'un tap précédent', (tester) async {
    final container = await pumpHarness(tester);
    // Simule une clé restée d'un tap antérieur.
    container.read(pendingFeedSectionKeyProvider.notifier).state = 'stale';

    PushNotificationService.routeIntent(
      NotificationIntent.parseFromLocalPayload('route:/digest', now: now),
    );
    await tester.pumpAndSettle();

    expect(container.read(pendingFeedSectionKeyProvider), isNull);
    expect(container.read(selectedEditionDateProvider), const EditionToday());
  });

  testWidgets(
      'alerte article : navigue sans toucher à l\'état d\'édition du feed',
      (tester) async {
    final container = await pumpHarness(tester);
    // L'utilisateur consultait une lettre passée avant de taper l'alerte.
    container.read(selectedEditionDateProvider.notifier).state =
        EditionPastDay(DateTime(2026, 8, 6));

    PushNotificationService.routeIntent(
      NotificationIntent.parseFromFcmData(
        {'route': '/flux-continu/content/abc', 'target_date': '2026-08-07'},
        now: now,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('article'), findsOneWidget);
    // Intouché : une cible non-feed ne doit pas réécrire l'édition courante.
    expect(
      container.read(selectedEditionDateProvider),
      EditionPastDay(DateTime(2026, 8, 6)),
    );
  });
}
