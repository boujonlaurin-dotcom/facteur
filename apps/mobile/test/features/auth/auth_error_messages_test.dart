import 'package:facteur/features/auth/utils/auth_error_messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthErrorMessages.translate', () {
    test('translates the anonymous password validation error', () {
      expect(
        AuthErrorMessages.translate(
          'Updating password of an anonymous user without an email or phone '
          'is not allowed',
        ),
        'Impossible de finaliser ton compte. Réessaie.',
      );
    });

    test('translates all known duplicate email variants', () {
      for (final message in [
        'User already registered',
        'Email address is already registered',
        'email_exists',
      ]) {
        expect(
          AuthErrorMessages.translate(message),
          'Cette adresse email est déjà utilisée.',
          reason: message,
        );
      }
    });

    test('translates the structured email rate limit code', () {
      expect(
        AuthErrorMessages.translate('over_email_send_rate_limit'),
        'Trop de tentatives. Réessaie dans quelques minutes.',
      );
    });

    // Cf. docs/bugs/bug-apple-sso-provider-not-enabled.md — message exact
    // renvoyé par GoTrue quand le provider Apple n'est pas activé côté
    // Supabase, tel qu'affiché à l'utilisateur dans Safari.
    test('translates a disabled OAuth provider into an actionable message', () {
      for (final message in [
        'Unsupported provider: provider is not enabled',
        'Provider is not enabled',
      ]) {
        final translated = AuthErrorMessages.translate(message);
        expect(translated, contains('momentanément indisponible'),
            reason: message);
        expect(translated, contains('email'), reason: message);
        // Jamais de jargon serveur dans l'UI.
        expect(translated.toLowerCase(), isNot(contains('provider')),
            reason: message);
      }
    });

    test('translates a rejected Apple nonce into a retry hint', () {
      expect(
        AuthErrorMessages.translate('Passed nonce and nonce in id_token '
            'should either both exist or not.'),
        'La connexion a expiré avant d\'aboutir. Réessaie.',
      );
    });

    test('translates an unauthorized Apple client id like a config outage', () {
      // Bundle ID absent des « Authorized Client IDs » du provider Apple.
      expect(
        AuthErrorMessages.translate('Invalid client: audience mismatch'),
        contains('momentanément indisponible'),
      );
    });

    test('treats both spellings of a user cancellation the same', () {
      for (final message in ['Sign in cancelled', 'Sign in canceled']) {
        expect(
          AuthErrorMessages.translate(message),
          'Connexion annulée.',
          reason: message,
        );
      }
    });
  });
}
