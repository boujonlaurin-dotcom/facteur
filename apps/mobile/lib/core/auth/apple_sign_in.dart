/// Flux natif « Sign in with Apple » (feuille système iOS/macOS).
///
/// Historiquement l'app passait par `signInWithOAuth(OAuthProvider.apple)`, qui
/// ouvre le navigateur sur `<projet>.supabase.co/auth/v1/authorize`. Ce détour
/// a deux défauts rédhibitoires, tous deux constatés en prod
/// (cf. docs/bugs/bug-apple-sso-provider-not-enabled.md) :
///
/// 1. toute erreur GoTrue s'affiche **dans le navigateur**, en JSON brut, hors
///    de portée de l'app — l'utilisateur voit
///    `{"code":400,...,"msg":"Unsupported provider: provider is not enabled"}`
///    au lieu d'un message en français ;
/// 2. Apple attend la feuille native (HIG « Sign in with Apple »), pas un
///    aller-retour Safari.
///
/// Le flux natif rend un `identityToken` échangé ensuite contre une session
/// Supabase via `signInWithIdToken` : tout se joue dans l'app, les erreurs sont
/// catchables, et Supabase n'a besoin que du **Bundle ID en client ID
/// autorisé** (ni Services ID ni clé secrète, requis seulement pour le web).
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Alphabet du nonce — caractères non réservés en URL, sûrs à transporter
/// tels quels dans le JWT Apple.
const String _nonceAlphabet =
    '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';

/// Nonce aléatoire à usage unique.
///
/// Le nonce **brut** part vers Supabase (`signInWithIdToken(nonce: ...)`), son
/// SHA-256 part vers Apple. Apple encode le hash dans l'`identityToken` et
/// GoTrue revérifie `sha256(nonce brut) == claim du token` : c'est ce qui
/// empêche le rejeu d'un token Apple intercepté.
String generateRawNonce({int length = 32, Random? random}) {
  final rng = random ?? Random.secure();
  return List<String>.generate(
    length,
    (_) => _nonceAlphabet[rng.nextInt(_nonceAlphabet.length)],
  ).join();
}

/// SHA-256 hexadécimal — la forme attendue par Apple pour le nonce.
String sha256OfString(String input) =>
    sha256.convert(utf8.encode(input)).toString();

/// Recompose « Prénom Nom » à partir de ce qu'Apple accepte de donner.
///
/// Les deux champs sont indépendamment nullables (l'utilisateur peut n'avoir
/// qu'un prénom), d'où le filtrage plutôt qu'une simple interpolation.
String? formatAppleFullName(String? givenName, String? familyName) {
  final parts = <String?>[givenName, familyName]
      .map((String? part) => part?.trim() ?? '')
      .where((String part) => part.isNotEmpty);
  if (parts.isEmpty) return null;
  return parts.join(' ');
}

/// Identité Apple obtenue de la feuille native, prête pour `signInWithIdToken`.
class AppleCredential {
  const AppleCredential({
    required this.idToken,
    required this.rawNonce,
    this.email,
    this.givenName,
    this.familyName,
  });

  /// JWT signé par Apple, échangé contre une session Supabase.
  final String idToken;

  /// Nonce **brut** (non hashé) correspondant au token — Supabase le rejoue.
  final String rawNonce;

  /// Email (réel ou relais `@privaterelay.appleid.com`), absent aux
  /// autorisations suivantes.
  final String? email;

  /// ⚠️ Apple ne transmet le nom qu'à la **toute première** autorisation d'un
  /// utilisateur pour ce bundle. Aux connexions suivantes ces champs sont
  /// `null` — d'où la persistance immédiate dans les métadonnées Supabase.
  final String? givenName;
  final String? familyName;

  String? get fullName => formatAppleFullName(givenName, familyName);
}

/// L'utilisateur a fermé la feuille Apple. Ce n'est pas une erreur : l'appelant
/// relâche l'état de chargement sans afficher de message.
class AppleSignInCancelledException implements Exception {
  const AppleSignInCancelledException();

  @override
  String toString() => 'AppleSignInCancelledException';
}

/// Échec du flux natif côté Apple (avant même d'atteindre Supabase).
class AppleSignInException implements Exception {
  const AppleSignInException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() =>
      'AppleSignInException(${code ?? 'unknown'}): $message';
}

/// Point d'injection : les tests substituent un double, la prod utilise
/// [NativeAppleAuthorizationRequester].
abstract class AppleAuthorizationRequester {
  Future<AppleCredential> request();
}

class NativeAppleAuthorizationRequester implements AppleAuthorizationRequester {
  const NativeAppleAuthorizationRequester();

  @override
  Future<AppleCredential> request() async {
    final rawNonce = generateRawNonce();

    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const <AppleIDAuthorizationScopes>[
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: sha256OfString(rawNonce),
      );

      final idToken = credential.identityToken;
      if (idToken == null || idToken.isEmpty) {
        // Apple a répondu sans JWT : rien à échanger contre une session.
        throw const AppleSignInException(
          'Apple n\'a pas renvoyé de jeton d\'identité.',
          code: 'missing_identity_token',
        );
      }

      return AppleCredential(
        idToken: idToken,
        rawNonce: rawNonce,
        email: credential.email,
        givenName: credential.givenName,
        familyName: credential.familyName,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw const AppleSignInCancelledException();
      }
      throw AppleSignInException(e.message, code: e.code.name);
    } on SignInWithAppleException catch (e) {
      throw AppleSignInException(e.toString(), code: 'platform');
    }
  }
}
