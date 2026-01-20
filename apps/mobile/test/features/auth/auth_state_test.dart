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
  });
}
