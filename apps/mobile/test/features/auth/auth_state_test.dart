import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:facteur/core/auth/auth_state.dart';

void main() {
  group('AuthState logic tests', () {
    test('isEmailConfirmed should return false if user is null', () {
      const state = AuthState(user: null);
      expect(state.isEmailConfirmed, isFalse);
    });

    test('isEmailConfirmed should return true if emailConfirmedAt is not null',
        () {
      final user = User(
        id: '123',
        appMetadata: {
          'provider': 'email',
          'providers': ['email']
        },
        userMetadata: {},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
        emailConfirmedAt: DateTime.now().toIso8601String(),
      );
      final state = AuthState(user: user);
      expect(state.isEmailConfirmed, isTrue);
    });

    test(
        'isEmailConfirmed should return false if provider is email and emailConfirmedAt is null',
        () {
      final user = User(
        id: '123',
        appMetadata: {
          'provider': 'email',
          'providers': ['email']
        },
        userMetadata: {},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
        emailConfirmedAt: null,
      );
      final state = AuthState(user: user);
      expect(state.isEmailConfirmed, isFalse);
    });

    test(
        'isEmailConfirmed should return true if provider is google even if emailConfirmedAt is null',
        () {
      final user = User(
        id: '123',
        appMetadata: {
          'provider': 'google',
          'providers': ['google']
        },
        userMetadata: {},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
        emailConfirmedAt: null,
      );
      final state = AuthState(user: user);
      expect(state.isEmailConfirmed, isTrue);
    });

    test(
        'isEmailConfirmed should return true if multiple providers include a social one',
        () {
      final user = User(
        id: '123',
        appMetadata: {
          'provider': 'email',
          'providers': ['email', 'apple']
        },
        userMetadata: {},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
        emailConfirmedAt: null,
      );
      final state = AuthState(user: user);
      expect(state.isEmailConfirmed, isTrue);
    });

    // --- Tests additionnels pour le bug "re-login après fermeture app" ---

    test('isAuthenticated should return false when user is null', () {
      const state = AuthState(user: null);
      expect(state.isAuthenticated, isFalse);
    });

    test('isAuthenticated should return true when user is set', () {
      final user = User(
        id: '123',
        appMetadata: {'provider': 'email', 'providers': ['email']},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
        emailConfirmedAt: DateTime.now().toIso8601String(),
      );
      final state = AuthState(user: user);
      expect(state.isAuthenticated, isTrue);
    });

    test(
        'forceUnconfirmed=true overrides isEmailConfirmed even if emailConfirmedAt is set',
        () {
      // Ce cas survient quand le backend renvoie 403 (stale JWT).
      // forceUnconfirmed empêche l'accès même avec une session techniquement valide.
      final user = User(
        id: '123',
        appMetadata: {'provider': 'email', 'providers': ['email']},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
        emailConfirmedAt: DateTime.now().toIso8601String(),
      );
      final state = AuthState(user: user, forceUnconfirmed: true);
      expect(state.isEmailConfirmed, isFalse,
          reason: 'forceUnconfirmed doit prendre la priorité sur emailConfirmedAt');
    });

    test('forceUnconfirmed=false does not block confirmed user', () {
      final user = User(
        id: '123',
        appMetadata: {'provider': 'email', 'providers': ['email']},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
        emailConfirmedAt: DateTime.now().toIso8601String(),
      );
      final state = AuthState(user: user, forceUnconfirmed: false);
      expect(state.isEmailConfirmed, isTrue);
    });

    test('isLoading=true initial state is correct (splash screen during restore)',
        () {
      // L'état initial d'AuthStateNotifier est isLoading:true.
      // Le router doit rester sur le splash pendant ce temps.
      const state = AuthState(isLoading: true);
      expect(state.isLoading, isTrue);
      expect(state.isAuthenticated, isFalse);
    });

    test('copyWith preserves user when not updated', () {
      final user = User(
        id: '123',
        appMetadata: {'provider': 'email', 'providers': ['email']},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
        emailConfirmedAt: DateTime.now().toIso8601String(),
      );
      final state = AuthState(user: user);
      final updated = state.copyWith(isLoading: false);
      expect(updated.user, equals(user));
    });

    test('copyWith(clearError: true) clears error field', () {
      const state = AuthState(error: 'some error');
      final cleared = state.copyWith(clearError: true);
      expect(cleared.error, isNull);
    });

    test(
        'Apple provider without emailConfirmedAt is treated as confirmed (same as Google)',
        () {
      final user = User(
        id: '123',
        appMetadata: {'provider': 'apple', 'providers': ['apple']},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
        emailConfirmedAt: null,
      );
      final state = AuthState(user: user);
      expect(state.isEmailConfirmed, isTrue,
          reason: 'Apple Sign-In doit être considéré comme confirmé d\'office');
    });
  });
}
