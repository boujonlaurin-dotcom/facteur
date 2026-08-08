import 'dart:io';

import 'package:flutter/material.dart';

import 'package:facteur/config/routes.dart';
import 'package:facteur/core/auth/auth_state.dart';
import 'package:facteur/core/services/push_notification_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

/// Verrou structurel du deep link des notifications.
///
/// Les alertes source et sujet (stories 30.2/30.3) ont émis `/article/<id>`
/// pendant toute leur mise en service — une route jamais enregistrée dans le
/// GoRouter : 100 % des taps tombaient sur « Page non trouvée ». Rien ne l'avait
/// détecté parce qu'aucun test ne confrontait les routes du payload serveur à la
/// table de routage réelle. C'est ce que fait ce fichier.
///
/// Cf. docs/bugs/bug-alerte-push-lien-introuvable.md.

const _contentId = '00000000-0000-4000-8000-0000000000a1';

/// Routes émises par le backend dans `data['route']`.
///
/// Miroir de `EMITTED_ROUTE_SHAPES` dans
/// `packages/api/tests/services/test_push_composer.py`, plus le dispatcher de
/// réengagement. Toute route ajoutée côté serveur doit l'être ici.
const backendPushRoutes = <String>[
  // push_composer.compose_daily_digest
  '/digest',
  // push_composer.compose_source_alert / compose_topic_alert
  '/flux-continu/content/$_contentId',
  // onboarding_reengagement_dispatcher
  '/onboarding',
];

/// Routes émises par les notifications LOCALES (`payload: 'route:…'`).
const localPushRoutes = <String>[
  '/digest',
  '/digest?serein=1',
  '/flux-continu',
];

/// Payload historique des alertes. Il dort encore dans les tiroirs de
/// notification et sort des binaires `production` en circulation : l'alias doit
/// survivre à la correction serveur.
const legacyAlertRoute = '/article/$_contentId';

class _FakeAuthStateNotifier extends AuthStateNotifier {
  _FakeAuthStateNotifier(super.initialState) : super.test();
}

AuthState _resolvedAuthState() => AuthState(
      user: User(
        id: '123',
        appMetadata: const {
          'provider': 'google',
          'providers': ['google'],
        },
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
      ),
      isLoading: false,
      needsOnboarding: false,
      onboardingStatusKnown: true,
    );

GoRouter _buildRouter() {
  final container = ProviderContainer(
    overrides: [
      authStateProvider
          .overrideWith((ref) => _FakeAuthStateNotifier(_resolvedAuthState())),
    ],
  );
  addTearDown(container.dispose);
  return container.read(routerProvider);
}

void main() {
  setUpAll(() {
    Hive.init(
      Directory.systemTemp.createTempSync('push_route_resolution_test').path,
    );
  });

  tearDown(PushNotificationService.clearPendingRoute);

  group('résolution des routes push dans le GoRouter', () {
    test('toute route émise par le backend matche une route enregistrée', () {
      final router = _buildRouter();
      for (final route in backendPushRoutes) {
        final match = router.configuration.findMatch(Uri.parse(route));
        expect(
          match.isError,
          isFalse,
          reason: 'Route push serveur non enregistrée : $route '
              '(elle tomberait sur l\'errorBuilder « Page non trouvée »)',
        );
      }
    });

    test('toute route des notifications locales matche une route enregistrée',
        () {
      final router = _buildRouter();
      for (final route in localPushRoutes) {
        final match = router.configuration.findMatch(Uri.parse(route));
        expect(match.isError, isFalse, reason: 'Route locale morte : $route');
      }
    });

    test('l\'ancien payload /article/<id> reste résolu (compat descendante)',
        () {
      final router = _buildRouter();
      final match = router.configuration.findMatch(Uri.parse(legacyAlertRoute));
      expect(
        match.isError,
        isFalse,
        reason: 'Les notifications déjà posées portent encore cette route',
      );
    });

    test('l\'alias /article/<id> vise la route article canonique', () {
      expect(articleRouteFor(_contentId), '/flux-continu/content/$_contentId');
      // Le serveur émet exactement cette cible : les deux bouts ne peuvent pas
      // diverger sans casser aussi le test Python jumeau.
      expect(backendPushRoutes, contains(articleRouteFor(_contentId)));
    });

    test('une route non enregistrée est bien rejetée (le test a des dents)',
        () {
      final router = _buildRouter();
      expect(
        router.configuration
            .findMatch(Uri.parse('/route-qui-nexiste-pas'))
            .isError,
        isTrue,
      );
      // `RoutePaths.contentDetail` est déclarée mais n'a jamais été
      // enregistrée : la preuve que le mécanisme détecte exactement la classe
      // de bug qui a tué les alertes.
      expect(
        router.configuration
            .findMatch(Uri.parse('/content/$_contentId'))
            .isError,
        isTrue,
      );
    });
  });

  group('cold-open : la cible push survit à la résolution de l\'auth', () {
    test('openRoute met la cible de côté quand le navigator n\'existe pas', () {
      PushNotificationService.openRoute(legacyAlertRoute);
      expect(PushNotificationService.takePendingRoute(), legacyAlertRoute);
      // Consommée une seule fois : pas de re-navigation fantôme.
      expect(PushNotificationService.takePendingRoute(), isNull);
    });

    test('clearPendingRoute libère la cible une fois un écran réel monté', () {
      PushNotificationService.openRoute(legacyAlertRoute);
      PushNotificationService.clearPendingRoute();
      expect(PushNotificationService.takePendingRoute(), isNull);
    });

    // Le `redirect` top-level est interrogé directement (et non via un
    // `MaterialApp.router` monté) : la seule chose à prouver est sa DÉCISION.
    // Monter le lecteur ferait dépendre le test d'un Supabase initialisé, qu'un
    // test unitaire n'a pas.
    testWidgets(
        'la cible parquée pendant `isLoading` est rejouée dès l\'auth résolue',
        (tester) async {
      final router = _buildRouter();
      final context = await _pumpBareContext(tester);

      // Tap en app froide : l'auth chargeait encore, la cible a été parquée.
      PushNotificationService.openRoute(legacyAlertRoute);

      // L'auth vient de se résoudre — on est encore sur le splash.
      expect(
        await _topRedirectFor(router, context, RoutePaths.splash),
        legacyAlertRoute,
      );
    });

    testWidgets('sans cible parquée, l\'atterrissage reste L\'Essentiel',
        (tester) async {
      final router = _buildRouter();
      final context = await _pumpBareContext(tester);

      expect(
        await _topRedirectFor(router, context, RoutePaths.splash),
        RoutePaths.fluxContinu,
      );
    });

    testWidgets('la cible est libérée dès qu\'un écran réel est atteint',
        (tester) async {
      final router = _buildRouter();
      final context = await _pumpBareContext(tester);

      PushNotificationService.openRoute(legacyAlertRoute);
      // App chaude : le `go` aboutit, le redirect laisse passer la cible…
      expect(
        await _topRedirectFor(router, context, RoutePaths.fluxContinu),
        isNull,
      );
      // …et la relâche, pour qu'un futur passage par le splash ne rouvre pas
      // un article déjà lu.
      expect(PushNotificationService.takePendingRoute(), isNull);
    });
  });
}

/// Un `BuildContext` nu : le `redirect` ne lit rien dessus, mais sa signature
/// l'exige.
Future<BuildContext> _pumpBareContext(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  return tester.element(find.byType(SizedBox));
}

/// Décision du `redirect` top-level pour [location].
Future<String?> _topRedirectFor(
  GoRouter router,
  BuildContext context,
  String location,
) async {
  final matchList = router.configuration.findMatch(Uri.parse(location));
  final state = router.configuration.buildTopLevelGoRouterState(matchList);
  return router.configuration.topRedirect(context, state);
}
