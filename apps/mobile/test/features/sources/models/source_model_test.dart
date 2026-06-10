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

    test('parses is_generic flag on premium_connection', () {
      final generic = Source.fromJson({
        'id': 'source-id',
        'name': 'Generic Paywalled',
        'type': 'article',
        'premium_connection': {
          'enabled': true,
          'login_url': 'https://example.com',
          'test_url': 'https://example.com',
          'is_generic': true,
        },
      });

      expect(generic.premiumConnection, isNotNull);
      expect(generic.premiumConnection!.isGeneric, isTrue);
    });

    test('is_generic defaults to false when absent', () {
      final curated = Source.fromJson({
        'id': 'source-id',
        'name': 'Curated Paywalled',
        'type': 'article',
        'premium_connection': {
          'enabled': true,
          'login_url': 'https://example.com/login',
          'test_url': 'https://example.com/test',
        },
      });

      expect(curated.premiumConnection, isNotNull);
      expect(curated.premiumConnection!.isGeneric, isFalse);
    });
  });

  group('Source.fromJson hasPaywall', () {
    test('parses has_paywall true', () {
      final source = Source.fromJson({
        'id': 'source-id',
        'name': 'Paywalled Source',
        'type': 'article',
        'has_paywall': true,
      });

      expect(source.hasPaywall, isTrue);
    });

    test('defaults has_paywall to false when absent', () {
      final source = Source.fromJson({
        'id': 'source-id',
        'name': 'Free Source',
        'type': 'article',
      });

      expect(source.hasPaywall, isFalse);
    });
  });
}
