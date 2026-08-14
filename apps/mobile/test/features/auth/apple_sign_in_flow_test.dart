import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import 'package:facteur/core/auth/apple_sign_in.dart';
import 'package:facteur/core/auth/auth_state.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockGoTrueClient extends Mock implements GoTrueClient {}

class _MockAuthResponse extends Mock implements AuthResponse {}

class _MockUserResponse extends Mock implements UserResponse {}

/// Double de la feuille native Apple : les tests ne peuvent pas franchir le
/// canal de plateforme.
class _FakeAppleRequester implements AppleAuthorizationRequester {
  _FakeAppleRequester(this._result);

  final Object _result;
  int calls = 0;

  @override
  Future<AppleCredential> request() async {
    calls++;
    final result = _result;
    if (result is AppleCredential) return result;
    throw result;
  }
}

User _user({Map<String, dynamic> metadata = const {}}) => User(
      id: 'apple-user',
      appMetadata: const {
        'provider': 'apple',
        'providers': ['apple'],
      },
      userMetadata: metadata,
      aud: 'authenticated',
      createdAt: DateTime.now().toIso8601String(),
    );

void main() {
  setUpAll(() {
    registerFallbackValue(OAuthProvider.apple);
    registerFallbackValue(UserAttributes());
  });

  setUp(() {
    // `signInWithApple` route vers le flux natif selon la plateforme.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('supportsNativeAppleSignIn', () {
    test('vrai sur iOS et macOS', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(AuthStateNotifier.supportsNativeAppleSignIn, isTrue);
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      expect(AuthStateNotifier.supportsNativeAppleSignIn, isTrue);
    });

    test('faux sur Android — pas de feuille native, donc pas de bouton', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(AuthStateNotifier.supportsNativeAppleSignIn, isFalse);
    });
  });

  group('signInWithApple — flux natif', () {
    late _MockSupabaseClient supabase;
    late _MockGoTrueClient auth;

    setUp(() {
      supabase = _MockSupabaseClient();
      auth = _MockGoTrueClient();
      when(() => supabase.auth).thenReturn(auth);
      when(() => auth.currentUser).thenReturn(_user());
      when(() => auth.updateUser(any()))
          .thenAnswer((_) async => _MockUserResponse());
    });

    test(
        'échange l\'identityToken contre une session en rejouant le nonce BRUT',
        () async {
      // Contrat de sécurité : Apple reçoit sha256(nonce), Supabase reçoit le
      // nonce brut. Envoyer le hash à Supabase ferait échouer la vérification.
      when(
        () => auth.signInWithIdToken(
          provider: any(named: 'provider'),
          idToken: any(named: 'idToken'),
          nonce: any(named: 'nonce'),
        ),
      ).thenAnswer((_) async => _MockAuthResponse());

      final requester = _FakeAppleRequester(
        const AppleCredential(
          idToken: 'apple-jwt',
          rawNonce: 'nonce-brut-123',
        ),
      );
      final notifier = AuthStateNotifier.test(
        const AuthState(),
        supabase: supabase,
        appleRequester: requester,
      );

      await notifier.signInWithApple();

      expect(requester.calls, 1);
      final List<dynamic> captured = verify(
        () => auth.signInWithIdToken(
          provider: captureAny(named: 'provider'),
          idToken: captureAny(named: 'idToken'),
          nonce: captureAny(named: 'nonce'),
        ),
      ).captured;
      expect(captured[0], OAuthProvider.apple);
      expect(captured[1], 'apple-jwt');
      expect(captured[2], 'nonce-brut-123');
      expect(notifier.state.error, isNull);
      // Aucun navigateur n'est ouvert : sur iOS on ne doit jamais construire
      // l'URL `/auth/v1/authorize` (le chemin qui affichait le JSON brut dans
      // Safari — docs/bugs/bug-apple-sso-provider-not-enabled.md).
      verifyNever(
        () => auth.getOAuthSignInUrl(
          provider: any(named: 'provider'),
          redirectTo: any(named: 'redirectTo'),
        ),
      );
    });

    test('persiste le nom Apple, livré une seule fois', () async {
      when(
        () => auth.signInWithIdToken(
          provider: any(named: 'provider'),
          idToken: any(named: 'idToken'),
          nonce: any(named: 'nonce'),
        ),
      ).thenAnswer((_) async => _MockAuthResponse());

      final notifier = AuthStateNotifier.test(
        const AuthState(),
        supabase: supabase,
        appleRequester: _FakeAppleRequester(
          const AppleCredential(
            idToken: 'apple-jwt',
            rawNonce: 'n',
            givenName: 'Ada',
            familyName: 'Lovelace',
          ),
        ),
      );

      await notifier.signInWithApple();

      final attributes =
          verify(() => auth.updateUser(captureAny())).captured.single
              as UserAttributes;
      final data = attributes.data! as Map<String, dynamic>;
      expect(data['first_name'], 'Ada');
      expect(data['last_name'], 'Lovelace');
      expect(data['full_name'], 'Ada Lovelace');
    });

    test('n\'écrase pas un nom déjà présent dans les métadonnées', () async {
      when(() => auth.currentUser)
          .thenReturn(_user(metadata: const {'first_name': 'Grace'}));
      when(
        () => auth.signInWithIdToken(
          provider: any(named: 'provider'),
          idToken: any(named: 'idToken'),
          nonce: any(named: 'nonce'),
        ),
      ).thenAnswer((_) async => _MockAuthResponse());

      final notifier = AuthStateNotifier.test(
        const AuthState(),
        supabase: supabase,
        appleRequester: _FakeAppleRequester(
          const AppleCredential(
            idToken: 'apple-jwt',
            rawNonce: 'n',
            givenName: 'Ada',
          ),
        ),
      );

      await notifier.signInWithApple();

      verifyNever(() => auth.updateUser(any()));
    });

    test('un échec de persistance du nom n\'invalide pas la connexion',
        () async {
      when(
        () => auth.signInWithIdToken(
          provider: any(named: 'provider'),
          idToken: any(named: 'idToken'),
          nonce: any(named: 'nonce'),
        ),
      ).thenAnswer((_) async => _MockAuthResponse());
      when(() => auth.updateUser(any()))
          .thenThrow(const AuthException('boom'));

      final notifier = AuthStateNotifier.test(
        const AuthState(),
        supabase: supabase,
        appleRequester: _FakeAppleRequester(
          const AppleCredential(
            idToken: 'apple-jwt',
            rawNonce: 'n',
            givenName: 'Ada',
          ),
        ),
      );

      await notifier.signInWithApple();

      expect(notifier.state.error, isNull);
      expect(notifier.state.isLoading, isFalse);
    });

    test(
        'annulation : relâche isLoading sans afficher d\'erreur '
        '(sinon les boutons sociaux restent grisés)', () async {
      final notifier = AuthStateNotifier.test(
        const AuthState(),
        supabase: supabase,
        appleRequester:
            _FakeAppleRequester(const AppleSignInCancelledException()),
      );

      await notifier.signInWithApple();

      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.error, isNull);
    });

    test(
        'provider désactivé côté Supabase : message français, dans l\'app, '
        'et isLoading relâché', () async {
      // Reproduction exacte de l\'incident : GoTrue répond
      // 400 validation_failed « Unsupported provider: provider is not enabled ».
      when(
        () => auth.signInWithIdToken(
          provider: any(named: 'provider'),
          idToken: any(named: 'idToken'),
          nonce: any(named: 'nonce'),
        ),
      ).thenThrow(
        const AuthException(
          'Unsupported provider: provider is not enabled',
          statusCode: '400',
        ),
      );

      final notifier = AuthStateNotifier.test(
        const AuthState(),
        supabase: supabase,
        appleRequester: _FakeAppleRequester(
          const AppleCredential(idToken: 'apple-jwt', rawNonce: 'n'),
        ),
      );

      await notifier.signInWithApple();

      expect(notifier.state.isLoading, isFalse);
      expect(
        notifier.state.error,
        contains('momentanément indisponible'),
      );
      expect(notifier.state.error, isNot(contains('provider')));
    });

    test('échec natif Apple : erreur traduite, pas de crash', () async {
      final notifier = AuthStateNotifier.test(
        const AuthState(),
        supabase: supabase,
        appleRequester: _FakeAppleRequester(
          const AppleSignInException(
            'Apple n\'a pas renvoyé de jeton d\'identité.',
            code: 'missing_identity_token',
          ),
        ),
      );

      await notifier.signInWithApple();

      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.error, isNotNull);
      verifyNever(
        () => auth.signInWithIdToken(
          provider: any(named: 'provider'),
          idToken: any(named: 'idToken'),
          nonce: any(named: 'nonce'),
        ),
      );
    });
  });
}
