import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:facteur/config/routes.dart';
import 'package:facteur/core/auth/auth_state.dart';
import 'package:facteur/features/auth/screens/email_confirmation_screen.dart';
import 'package:facteur/features/flux_continu/services/tournee_progress_service.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
// For debugPrint

// Simple stub for AuthStateNotifier to control state in tests
class FakeAuthStateNotifier extends AuthStateNotifier {
  FakeAuthStateNotifier(AuthState initialState) : super.test(initialState);
}

/// Utilisateur social confirmé + onboardé (pas d'email confirmation, pas
/// d'onboarding) — l'état d'entrée du gate Rituel.
User _confirmedSocialUser() => User(
      id: '123',
      appMetadata: const {
        'provider': 'google',
        'providers': ['google'],
      },
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: DateTime.now().toIso8601String(),
    );

/// Chemin actuellement matché par [router] (après résolution des redirects).
String _currentPath(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.path;

/// Surface haute (téléphone) : `/edition` monte le loader du rituel dont la
/// citation éditoriale se révèle à 600 ms — dans la fenêtre de test 600 px par
/// défaut, la colonne déborde de ~23 px et fait échouer le test par intermittence.
/// Une hauteur réaliste supprime ce faux négatif (le test ne juge que le chemin).
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(600, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUpAll(() {
    Hive.init(
      Directory.systemTemp.createTempSync('router_redirection_test').path,
    );
  });

  testWidgets(
      'Router should redirect to EmailConfirmationScreen if user is logged in but unconfirmed',
      (WidgetTester tester) async {
    // 1. Prepare an unconfirmed state
    final unconfirmedUser = User(
      id: '123',
      appMetadata: {
        'provider': 'email',
        'providers': ['email']
      },
      userMetadata: {},
      aud: 'authenticated',
      createdAt: DateTime.now().toIso8601String(),
    );

    // Using a simple object to simulate a User because we can't easily instantiate a real User without all fields
    // Actually User() constructor might be internal or complex. Let's see if we can use a mock or a fake.

    final initialState = AuthState(
      user: unconfirmedUser,
      isLoading: false,
    );

    // 2. Setup the provider container with overridden auth state
    final container = ProviderContainer(
      overrides: [
        authStateProvider
            .overrideWith((ref) => FakeAuthStateNotifier(initialState)),
      ],
    );

    final router = container.read(routerProvider);

    // 3. Build the app with the real router
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
        ),
      ),
    );

    // 4. Wait for redirection
    await tester.pumpAndSettle();

    // 5. VERIFY: We should be on the EmailConfirmationScreen
    expect(find.byType(EmailConfirmationScreen), findsOneWidget);
    expect(find.text('Vérifie ta boîte mail !'), findsOneWidget);

    debugPrint(
        '✅ SUCCESS: Router correctly redirected unconfirmed user to EmailConfirmationScreen');
  });

  testWidgets(
      'Router should NOT redirect confirmed user to EmailConfirmationScreen',
      (WidgetTester tester) async {
    // 1. Prepare a confirmed state (mock date for confirmation)
    final confirmedUser = User(
      id: '123',
      appMetadata: {
        'provider': 'email',
        'providers': ['email']
      },
      userMetadata: {},
      aud: 'authenticated',
      createdAt: DateTime.now().toIso8601String(),
    );
    // Note: Since we can't easily mock User.emailConfirmedAt because it's a getter on a final field usually,
    // we would need a proper way to create a confirmed user.
    // In auth_state.dart, isEmailConfirmed checks user?.emailConfirmedAt != null.
    // Let's hope the User constructor works as expected or we use a social provider which is auto-confirmed.

    final socialUser = User(
      id: '123',
      appMetadata: {
        'provider': 'google',
        'providers': ['google']
      },
      userMetadata: {},
      aud: 'authenticated',
      createdAt: DateTime.now().toIso8601String(),
    );

    final initialState = AuthState(
      user: socialUser,
      isLoading: false,
      needsOnboarding: false,
      onboardingStatusKnown: true,
    );

    final container = ProviderContainer(
      overrides: [
        authStateProvider
            .overrideWith((ref) => FakeAuthStateNotifier(initialState)),
      ],
    );

    final router = container.read(routerProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 5. VERIFY: We should NOT be on the EmailConfirmationScreen
    expect(find.byType(EmailConfirmationScreen), findsNothing);
    debugPrint(
        '✅ SUCCESS: Confirmed user was not redirected to confirmation screen');
  });

  // ---------------------------------------------------------------------------
  // La « Lettre du jour » ne gate plus L'Essentiel (décision PO 02/08/2026) :
  // le gate quotidien /flux-continu → /edition a été retiré. Cold-boot et tap
  // onglet atterrissent directement sur L'Essentiel, que le rituel ait été vu
  // ou non. La lettre n'est plus jouée qu'en fin d'onboarding.
  // ---------------------------------------------------------------------------
  testWidgets(
      'La Lettre ne gate plus : cold-boot (rituel jamais vu) atterrit '
      'directement sur /flux-continu et le tap onglet y reste',
      (WidgetTester tester) async {
    _useTallSurface(tester);
    // Aucune clé « rituel vu » : avant, ce cold-boot passait par /edition.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();

    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith(
          (ref) => FakeAuthStateNotifier(
            AuthState(
              user: _confirmedSocialUser(),
              isLoading: false,
              needsOnboarding: false,
              onboardingStatusKnown: true,
            ),
          ),
        ),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);

    final router = container.read(routerProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Atterrissage post-auth : directement L'Essentiel, plus de /edition.
    expect(_currentPath(router), RoutePaths.fluxContinu);

    // Tap onglet « L'Essentiel » (main_shell fait `context.go(/flux-continu)`) :
    // aucun re-route vers la lettre.
    router.go(RoutePaths.fluxContinu);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(_currentPath(router), RoutePaths.fluxContinu);
  });

  // ---------------------------------------------------------------------------
  // Story 9.8 « L'Essentiel dynamique au retour » : l'auto-redirect « déjà
  // parcouru → Flâner » est retiré. L'atterrissage post-auth reste TOUJOURS
  // L'Essentiel, même une fois la tournée du jour parcourue.
  // ---------------------------------------------------------------------------
  testWidgets(
      'Story 9.8: L\'Essentiel déjà parcouru ne renvoie plus vers Flâner',
      (WidgetTester tester) async {
    _useTallSurface(tester);
    // Rituel vu (pas de /edition) + Essentiel déjà parcouru aujourd'hui :
    // avant la story 9.8, postAuthHomePath renvoyait vers /flaner.
    SharedPreferences.setMockInitialValues(<String, Object>{
      TourneeProgressService.morningRitualPrefsKey(DateTime.now()): true,
      TourneeProgressService.essentielViewedPrefsKey(DateTime.now()): true,
    });
    final prefs = await SharedPreferences.getInstance();

    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith(
          (ref) => FakeAuthStateNotifier(
            AuthState(
              user: _confirmedSocialUser(),
              isLoading: false,
              needsOnboarding: false,
              onboardingStatusKnown: true,
            ),
          ),
        ),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);

    final router = container.read(routerProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Atterrissage post-auth : toujours L'Essentiel, jamais Flâner.
    expect(_currentPath(router), RoutePaths.fluxContinu);
    expect(_currentPath(router), isNot(RoutePaths.flaner));
  });
}
