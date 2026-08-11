import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:facteur/core/auth/auth_state.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockGoTrueClient extends Mock implements GoTrueClient {}

class _MockUserResponse extends Mock implements UserResponse {}

void main() {
  late Directory hiveDirectory;

  setUpAll(() async {
    registerFallbackValue(UserAttributes());
    hiveDirectory = await Directory.systemTemp.createTemp(
      'facteur-auth-state-test-',
    );
    Hive.init(hiveDirectory.path);
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

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
      expect(state.isAuthenticated, isTrue);
    });

    test(
        'forceUnconfirmed=true overrides isEmailConfirmed even if emailConfirmedAt is set',
        () {
      // Ce cas survient quand le backend renvoie 403 (stale JWT).
      // forceUnconfirmed empêche l'accès même avec une session techniquement valide.
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
      final state = AuthState(user: user, forceUnconfirmed: true);
      expect(state.isEmailConfirmed, isFalse,
          reason:
              'forceUnconfirmed doit prendre la priorité sur emailConfirmedAt');
    });

    test('forceUnconfirmed=false does not block confirmed user', () {
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
      final state = AuthState(user: user, forceUnconfirmed: false);
      expect(state.isEmailConfirmed, isTrue);
    });

    test(
        'isLoading=true initial state is correct (splash screen during restore)',
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
        appMetadata: {
          'provider': 'apple',
          'providers': ['apple']
        },
        userMetadata: {},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
        emailConfirmedAt: null,
      );
      final state = AuthState(user: user);
      expect(state.isEmailConfirmed, isTrue,
          reason: 'Apple Sign-In doit être considéré comme confirmé d\'office');
    });

    // --- Tests pour lastTokenRefreshAt (signal d'invalidation feedProvider) ---
    //
    // Bug : au resume après JWT expiré, refreshUser() rafraîchissait le token
    // Supabase MAIS ne signalait pas aux data providers qu'ils pouvaient
    // re-fetcher. Conséquence : feedProvider continuait de servir du state
    // stale, et la première requête partait avec l'ancien JWT → 403.
    //
    // Fix : `lastTokenRefreshAt` est bumpé à chaque event `tokenRefreshed`
    // reçu du listener Supabase. Les providers qui `ref.watch(authStateProvider)`
    // voient une nouvelle identité d'AuthState et rebuildent.
    //
    // Cf. docs/bugs/bug-feed-403-auth-recovery.md.
    test('lastTokenRefreshAt default is null', () {
      const state = AuthState();
      expect(state.lastTokenRefreshAt, isNull);
    });

    test('copyWith(lastTokenRefreshAt: now) sets the field', () {
      const state = AuthState();
      final ts = DateTime.now();
      final updated = state.copyWith(lastTokenRefreshAt: ts);
      expect(updated.lastTokenRefreshAt, ts);
    });

    test('copyWith without lastTokenRefreshAt preserves the previous value',
        () {
      final ts = DateTime.utc(2026, 1, 1);
      final state = AuthState(lastTokenRefreshAt: ts);
      final updated = state.copyWith(isLoading: true);
      expect(updated.lastTokenRefreshAt, ts,
          reason: 'copyWith must not wipe lastTokenRefreshAt when not passed');
    });

    test(
        'two copyWith with different lastTokenRefreshAt produce distinct AuthState instances '
        '(Riverpod listeners rebuild)', () {
      final t1 = DateTime.utc(2026, 1, 1, 10, 0, 0);
      final t2 = DateTime.utc(2026, 1, 1, 10, 45, 0);
      final s1 = AuthState(lastTokenRefreshAt: t1);
      final s2 = s1.copyWith(lastTokenRefreshAt: t2);
      expect(identical(s1, s2), isFalse);
      expect(s1.lastTokenRefreshAt, t1);
      expect(s2.lastTokenRefreshAt, t2);
    });

    test('passwordRecoveryPending defaults to false', () {
      const state = AuthState();
      expect(state.passwordRecoveryPending, isFalse);
    });

    test('copyWith can mark password recovery pending', () {
      const state = AuthState();
      final updated = state.copyWith(passwordRecoveryPending: true);
      expect(updated.passwordRecoveryPending, isTrue);
    });
  });

  group('anonymous account conversion', () {
    test('does not mark an auto-confirmed email as pending', () async {
      final supabase = _MockSupabaseClient();
      final auth = _MockGoTrueClient();
      final response = _MockUserResponse();
      final confirmedUser = User(
        id: 'confirmed-user',
        appMetadata: const {'providers': ['email']},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
        emailConfirmedAt: DateTime.now().toIso8601String(),
      );

      when(() => supabase.auth).thenReturn(auth);
      when(() => auth.currentUser).thenReturn(confirmedUser);
      when(
        () => auth.updateUser(
          any(),
          emailRedirectTo: any(named: 'emailRedirectTo'),
        ),
      ).thenAnswer((_) async => response);
      final box = await Hive.openBox<dynamic>('auth_prefs');
      await box.put('pending_email_confirmation', 'ancien@example.com');

      final notifier = AuthStateNotifier.test(
        const AuthState(pendingEmailConfirmation: 'ancien@example.com'),
        supabase: supabase,
      );
      final converted = await notifier.convertAnonymousToAccount(
        email: 'nouveau@example.com',
        password: 'secret123',
      );

      expect(converted, isTrue);
      expect(notifier.state.pendingEmailConfirmation, isNull);
      expect(box.get('pending_email_confirmation'), isNull);
    });

    test('marks an unconfirmed email as pending', () async {
      final supabase = _MockSupabaseClient();
      final auth = _MockGoTrueClient();
      final response = _MockUserResponse();
      final unconfirmedUser = User(
        id: 'unconfirmed-user',
        appMetadata: const {'providers': ['email']},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
      );

      when(() => supabase.auth).thenReturn(auth);
      when(() => auth.currentUser).thenReturn(unconfirmedUser);
      when(
        () => auth.updateUser(
          any(),
          emailRedirectTo: any(named: 'emailRedirectTo'),
        ),
      ).thenAnswer((_) async => response);

      final notifier = AuthStateNotifier.test(
        const AuthState(),
        supabase: supabase,
      );
      final converted = await notifier.convertAnonymousToAccount(
        email: 'nouveau@example.com',
        password: 'secret123',
      );

      final box = Hive.box<dynamic>('auth_prefs');
      expect(converted, isTrue);
      expect(
        notifier.state.pendingEmailConfirmation,
        'nouveau@example.com',
      );
      expect(
        box.get('pending_email_confirmation'),
        'nouveau@example.com',
      );
    });

    test('partial conversion retry skips an email already attached', () async {
      final supabase = _MockSupabaseClient();
      final auth = _MockGoTrueClient();
      final response = _MockUserResponse();
      final userWithEmail = User(
        id: 'partial-user',
        appMetadata: const {'providers': ['email']},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
        email: 'nouveau@example.com',
        emailConfirmedAt: DateTime.now().toIso8601String(),
      );
      final seenAttributes = <UserAttributes>[];

      when(() => supabase.auth).thenReturn(auth);
      when(() => auth.currentUser).thenReturn(userWithEmail);
      when(
        () => auth.updateUser(
          any(),
          emailRedirectTo: any(named: 'emailRedirectTo'),
        ),
      ).thenAnswer((invocation) async {
        seenAttributes.add(
          invocation.positionalArguments.single as UserAttributes,
        );
        return response;
      });

      final notifier = AuthStateNotifier.test(
        const AuthState(),
        supabase: supabase,
      );
      final converted = await notifier.convertAnonymousToAccount(
        email: 'NOUVEAU@example.com',
        password: 'secret123',
      );

      expect(converted, isTrue);
      expect(seenAttributes, hasLength(1));
      expect(seenAttributes.single.email, isNull);
      expect(seenAttributes.single.password, 'secret123');
      expect(notifier.state.pendingEmailConfirmation, isNull);
    });

    test('sets email before password and reports a partial failure', () async {
      final supabase = _MockSupabaseClient();
      final auth = _MockGoTrueClient();
      final response = _MockUserResponse();
      final seenAttributes = <UserAttributes>[];
      final seenRedirects = <String?>[];

      when(() => supabase.auth).thenReturn(auth);
      when(
        () => auth.updateUser(
          any(),
          emailRedirectTo: any(named: 'emailRedirectTo'),
        ),
      ).thenAnswer((invocation) async {
        seenAttributes.add(
          invocation.positionalArguments.single as UserAttributes,
        );
        seenRedirects.add(
          invocation.namedArguments[#emailRedirectTo] as String?,
        );
        if (seenAttributes.length == 2) {
          throw const AuthException('Password update failed');
        }
        return response;
      });

      final notifier = AuthStateNotifier.test(
        const AuthState(),
        supabase: supabase,
      );
      final converted = await notifier.convertAnonymousToAccount(
        email: 'nouveau@example.com',
        password: 'secret123',
      );

      expect(converted, isFalse);
      expect(seenAttributes, hasLength(2));
      expect(seenAttributes[0].email, 'nouveau@example.com');
      expect(seenAttributes[0].password, isNull);
      expect(seenRedirects[0], isNotNull);
      expect(seenAttributes[1].email, isNull);
      expect(seenAttributes[1].password, 'secret123');
      expect(seenRedirects[1], isNull);
      expect(notifier.state.pendingEmailConfirmation, isNull);
      expect(
        notifier.state.error,
        'Impossible de définir ton mot de passe. Réessaie ou utilise '
        '« Mot de passe oublié ».',
      );
    });
  });
}
