import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:facteur/core/auth/auth_state.dart' as app_auth;
import 'package:facteur/features/digest/providers/serein_toggle_provider.dart';

app_auth.AuthState _authState(String? userId) {
  if (userId == null) return const app_auth.AuthState();
  return app_auth.AuthState(
    user: supabase.User(
      id: userId,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2023-01-01',
    ),
  );
}

/// Controllable fake so tests can flip the signed-in user at will.
class _FakeAuthNotifier extends StateNotifier<app_auth.AuthState>
    implements app_auth.AuthStateNotifier {
  _FakeAuthNotifier(String? userId) : super(_authState(userId));

  void setUser(String? userId) => state = _authState(userId);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProviderContainer _container(_FakeAuthNotifier auth) {
  final container = ProviderContainer(
    overrides: [
      app_auth.authStateProvider.overrideWith((ref) => auth),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('SereinToggleNotifier.initFromApi idempotency', () {
    test('first call syncs with the server value and clears loading', () {
      final container = _container(_FakeAuthNotifier('userA'));
      expect(container.read(sereinToggleProvider).isLoading, isTrue);

      container.read(sereinToggleProvider.notifier).initFromApi(true);

      final state = container.read(sereinToggleProvider);
      expect(state.enabled, isTrue);
      expect(state.isLoading, isFalse);
    });

    test('subsequent calls never overwrite the stabilised choice', () {
      final container = _container(_FakeAuthNotifier('userA'));
      final notifier = container.read(sereinToggleProvider.notifier);

      notifier.initFromApi(true); // first load → enabled, no longer loading
      // A digest re-fetch returns the (stale) default — must be ignored.
      notifier.initFromApi(false);

      expect(container.read(sereinToggleProvider).enabled, isTrue);
    });

    test('setEnabledLocal keeps isLoading so the first sync still confirms', () {
      final container = _container(_FakeAuthNotifier('userA'));
      final notifier = container.read(sereinToggleProvider.notifier);

      // Pré-réglage post-onboarding avant que /digest/both ait répondu.
      notifier.setEnabledLocal(true);
      expect(container.read(sereinToggleProvider).enabled, isTrue);
      expect(container.read(sereinToggleProvider).isLoading, isTrue);

      // /digest/both confirme la préférence serveur.
      notifier.initFromApi(true);
      expect(container.read(sereinToggleProvider).enabled, isTrue);
      expect(container.read(sereinToggleProvider).isLoading, isFalse);
    });
  });

  group('SereinToggleNotifier auth lifecycle', () {
    test('resets to a fresh loading state when the user changes', () {
      final auth = _FakeAuthNotifier('userA');
      final container = _container(auth);

      // User A: serein synced ON, stabilised.
      container.read(sereinToggleProvider.notifier).initFromApi(true);
      expect(container.read(sereinToggleProvider).enabled, isTrue);
      expect(container.read(sereinToggleProvider).isLoading, isFalse);

      // Logout then a different account on the same device.
      auth.setUser(null);
      auth.setUser('userB');

      // The notifier is rebuilt fresh → the guard no longer blocks the new
      // user's sync, so userB's OFF preference applies correctly.
      final fresh = container.read(sereinToggleProvider);
      expect(fresh.isLoading, isTrue);
      expect(fresh.enabled, isFalse);

      container.read(sereinToggleProvider.notifier).initFromApi(false);
      expect(container.read(sereinToggleProvider).enabled, isFalse);
    });
  });
}
