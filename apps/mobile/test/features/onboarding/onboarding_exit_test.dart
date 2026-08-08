import 'dart:io';

import 'package:facteur/config/routes.dart';
import 'package:facteur/core/auth/auth_state.dart';
import 'package:facteur/features/flux_continu/services/tournee_progress_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

/// Bug onboarding iOS — sortie du questionnaire par la croix (X).
///
/// La croix n'est rendue que pour une session **non-anonyme** (un vrai compte
/// qui refait son onboarding, ou une session périmée restaurée du keychain
/// iOS). Le nouveau handler attend la fermeture **complète** du dialog (résolution
/// de `showDialog`) avant de muter `needsOnboarding`, pour ne plus faire courir
/// GoRouter contre le navigateur racine encore en animation de fermeture.
///
/// Ce test couvre le happy path du flux de sortie et la **validité de la
/// destination** (Fix 3) : tap croix → « Quitter » → aucune exception,
/// atterrissage sur une route montable (/flux-continu). La course d'animation
/// elle-même n'est pas reproductible avec des `pump` discrets en widget test
/// (l'ancien code passe aussi ce test) — elle se valide sur device iPhone.
class FakeAuthStateNotifier extends AuthStateNotifier {
  FakeAuthStateNotifier(AuthState initialState) : super.test(initialState);
}

/// Session non-anonyme confirmée mais qui doit encore s'onboarder — l'état qui
/// affiche la croix de sortie.
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

String _currentPath(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.path;

void main() {
  setUpAll(() {
    Hive.init(
      Directory.systemTemp.createTempSync('onboarding_exit_test').path,
    );
  });

  testWidgets(
      'sortie par la croix : « Quitter » ne crash pas et atterrit sur '
      '/flux-continu', (WidgetTester tester) async {
    // Surface haute (téléphone) pour éviter les débordements de layout.
    tester.view.physicalSize = const Size(600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();

    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith(
          (ref) => FakeAuthStateNotifier(
            AuthState(
              user: _confirmedSocialUser(),
              isLoading: false,
              needsOnboarding: true,
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
    // Résolution initiale : /splash → /onboarding (needsOnboarding).
    await tester.pump();
    expect(_currentPath(router), RoutePaths.onboarding);

    // Ouvre la confirmation via la croix (visible car session non-anonyme).
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Quitter'), findsOneWidget);

    // Confirme la sortie : pump à travers l'animation de fermeture du dialog
    // (~200 ms) puis le refresh GoRouter. C'est pendant cette fenêtre que
    // l'ancien code faisait crasher le navigateur racine.
    await tester.tap(find.text('Quitter'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(_currentPath(router), RoutePaths.fluxContinu);
  });
}
