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
  });
}
