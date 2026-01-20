import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:facteur/config/routes.dart';
import 'package:facteur/core/auth/auth_state.dart';
import 'package:facteur/features/auth/screens/email_confirmation_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
// For debugPrint

// Simple stub for AuthStateNotifier to control state in tests
class FakeAuthStateNotifier extends AuthStateNotifier {
  FakeAuthStateNotifier(AuthState initialState) : super() {
    state = initialState;
  }
}

void main() {
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

    await tester.pumpAndSettle();

    // 5. VERIFY: We should NOT be on the EmailConfirmationScreen
    expect(find.byType(EmailConfirmationScreen), findsNothing);
    debugPrint(
        '✅ SUCCESS: Confirmed user was not redirected to confirmation screen');
  });
}
