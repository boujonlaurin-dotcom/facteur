import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/sources/models/source_model.dart';

void main() {
  group('Source.fromJson premiumConnection', () {
    test('parses usable premium_connection', () {
      final source = Source.fromJson({
        'id': 'source-id',
        'name': 'Premium Source',
        'type': 'article',
        'premium_connection': {
          'enabled': true,
          'login_url': ' https://example.com/login ',
          'test_url': ' https://example.com/test ',
          'display_hint': 'Connectez-vous',
        },
      });

      expect(source.premiumConnection, isNotNull);
      expect(source.premiumConnection!.loginUrl, 'https://example.com/login');
      expect(source.premiumConnection!.testUrl, 'https://example.com/test');
      expect(source.premiumConnection!.displayHint, 'Connectez-vous');
    });

    test('ignores malformed premium_connection defensively', () {
      final source = Source.fromJson({
        'id': 'source-id',
        'name': 'Regular Source',
        'type': 'article',
        'premium_connection': ['not', 'a', 'map'],
      });

      expect(source.premiumConnection, isNull);
    });

    test('ignores incomplete premium_connection', () {
      final source = Source.fromJson({
        'id': 'source-id',
        'name': 'Regular Source',
        'type': 'article',
        'premium_connection': {
          'enabled': true,
          'login_url': 'https://example.com/login',
        },
      });

      expect(source.premiumConnection, isNull);
    });
  });
}
