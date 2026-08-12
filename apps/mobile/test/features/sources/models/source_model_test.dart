import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/sources/models/source_model.dart';

void main() {
  group('resolvePremiumConnection', () {
    test('uses curated connection when available', () {
      const curated = PremiumConnection(
        loginUrl: 'https://example.com/login',
        testUrl: 'https://example.com/article',
      );
      final source = Source(
        id: 'source',
        name: 'Source',
        type: SourceType.article,
        hasPaywall: true,
        premiumConnection: curated,
      );

      expect(resolvePremiumConnection(source), same(curated));
    });

    test('creates a generic fallback for a paid source with a valid URL', () {
      final source = Source(
        id: 'source',
        name: 'Source',
        type: SourceType.article,
        url: 'https://example.com',
        hasPaywall: true,
      );

      final connection = resolvePremiumConnection(source);

      expect(connection, isNotNull);
      expect(connection!.isGeneric, isTrue);
      // Le flux générique est synthétisé sur l'origine du site (slash final).
      expect(connection.loginUrl, 'https://example.com/');
      expect(connection.testUrl, 'https://example.com/');
    });

    test('normalizes a feed URL to the site origin (bug Cerveau & Psycho)', () {
      final source = Source(
        id: 'feed',
        name: 'Cerveau & Psycho',
        type: SourceType.article,
        url: 'https://www.cerveauetpsycho.fr/rss.xml',
        hasPaywall: true,
      );

      final connection = resolvePremiumConnection(source);

      expect(connection, isNotNull);
      expect(connection!.loginUrl, 'https://www.cerveauetpsycho.fr/');
      expect(connection.testUrl, 'https://www.cerveauetpsycho.fr/');
    });

    test('rejects free sources and paid sources without a valid URL', () {
      final free = Source(
        id: 'free',
        name: 'Free',
        type: SourceType.article,
        url: 'https://example.com',
      );
      final invalid = Source(
        id: 'invalid',
        name: 'Invalid',
        type: SourceType.article,
        url: 'example.com',
        hasPaywall: true,
      );

      expect(resolvePremiumConnection(free), isNull);
      expect(resolvePremiumConnection(invalid), isNull);
    });
  });

  group('forceGenericConnection', () {
    test('reuses the existing usable connection (curated or explicit)', () {
      const curated = PremiumConnection(
        loginUrl: 'https://example.com/login',
        testUrl: 'https://example.com/article',
      );
      final source = Source(
        id: 'source',
        name: 'Source',
        type: SourceType.article,
        hasPaywall: true,
        premiumConnection: curated,
      );

      expect(forceGenericConnection(source), same(curated));
    });

    test('synthesizes a generic connection for a free source with http url', () {
      final source = Source(
        id: 'free',
        name: 'Free Followed',
        type: SourceType.article,
        url: 'https://nytimes.com',
      );

      final connection = forceGenericConnection(source);

      expect(connection, isNotNull);
      expect(connection!.isGeneric, isTrue);
      // Origine du site (slash final), jamais l'URL brute.
      expect(connection.loginUrl, 'https://nytimes.com/');
      expect(connection.testUrl, 'https://nytimes.com/');
    });

    test('returns null without a valid http(s) url', () {
      final source = Source(
        id: 'nourl',
        name: 'No URL',
        type: SourceType.article,
        url: 'example.com',
      );

      expect(forceGenericConnection(source), isNull);
      expect(
        forceGenericConnection(
          Source(id: 'nil', name: 'Nil', type: SourceType.article),
        ),
        isNull,
      );
    });
  });

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

  group('Source.fromJson canConnectLogin', () {
    test('parses the backend capability flag', () {
      final source = Source.fromJson({
        'id': 'source-id',
        'name': 'Free Source',
        'type': 'article',
        'can_connect_login': true,
      });

      expect(source.canConnectLogin, isTrue);
    });

    test('defaults to the previous premium behavior when absent', () {
      final free = Source.fromJson({
        'id': 'free-id',
        'name': 'Free Source',
        'type': 'article',
      });
      final paid = Source.fromJson({
        'id': 'paid-id',
        'name': 'Paid Source',
        'type': 'article',
        'has_paywall': true,
      });

      expect(free.canConnectLogin, isFalse);
      expect(paid.canConnectLogin, isTrue);
    });
  });

  group('resolveOnboardingLoginConnection', () {
    test('connects a regular HTTP source without a paywall', () {
      final source = Source(
        id: 'free',
        name: 'Free Source',
        type: SourceType.article,
        url: 'https://example.com/articles',
        canConnectLogin: true,
      );

      final connection = resolveOnboardingLoginConnection(source);

      expect(connection, isNotNull);
      expect(connection!.isGeneric, isTrue);
      expect(connection.loginUrl, 'https://example.com/');
    });

    test('keeps curated connections and blocks explicit opt-outs', () {
      const curated = PremiumConnection(
        loginUrl: 'https://example.com/login',
        testUrl: 'https://example.com/article',
      );
      final source = Source(
        id: 'curated',
        name: 'Curated Source',
        type: SourceType.article,
        canConnectLogin: true,
        premiumConnection: curated,
      );
      final blocked = Source(
        id: 'blocked',
        name: 'Blocked Source',
        type: SourceType.article,
        url: 'https://example.com',
        canConnectLogin: false,
      );

      expect(resolveOnboardingLoginConnection(source), same(curated));
      expect(resolveOnboardingLoginConnection(blocked), isNull);
    });
  });
}
