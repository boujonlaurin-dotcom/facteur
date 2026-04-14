import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/sources/models/smart_search_result.dart';

void main() {
  group('SmartSearchResult.fromJson', () {
    test('parses complete JSON correctly', () {
      final json = {
        'name': 'Le Monde',
        'type': 'article',
        'url': 'https://lemonde.fr',
        'feed_url': 'https://lemonde.fr/rss/une.xml',
        'favicon_url': 'https://lemonde.fr/favicon.ico',
        'description': 'Journal francais',
        'in_catalog': true,
        'is_curated': true,
        'source_id': '123e4567-e89b-12d3-a456-426614174000',
        'recent_items': [
          {'title': 'Article 1', 'published_at': '2025-01-01'},
          {'title': 'Article 2', 'published_at': '2025-01-02'},
          {'title': 'Article 3', 'published_at': '2025-01-03'},
        ],
        'score': 0.95,
        'source_layer': 'catalog',
      };

      final result = SmartSearchResult.fromJson(json);

      expect(result.name, 'Le Monde');
      expect(result.type, 'article');
      expect(result.url, 'https://lemonde.fr');
      expect(result.feedUrl, 'https://lemonde.fr/rss/une.xml');
      expect(result.faviconUrl, 'https://lemonde.fr/favicon.ico');
      expect(result.description, 'Journal francais');
      expect(result.inCatalog, true);
      expect(result.isCurated, true);
      expect(result.sourceId, '123e4567-e89b-12d3-a456-426614174000');
      expect(result.recentItems, hasLength(3));
      expect(result.recentItems[0].title, 'Article 1');
      expect(result.score, 0.95);
      expect(result.sourceLayer, 'catalog');
    });

    test('handles missing fields with defaults', () {
      final json = <String, dynamic>{};

      final result = SmartSearchResult.fromJson(json);

      expect(result.name, 'Source inconnue');
      expect(result.type, 'article');
      expect(result.url, '');
      expect(result.feedUrl, '');
      expect(result.faviconUrl, isNull);
      expect(result.description, isNull);
      expect(result.inCatalog, false);
      expect(result.isCurated, false);
      expect(result.sourceId, isNull);
      expect(result.recentItems, isEmpty);
      expect(result.score, 0.0);
      expect(result.sourceLayer, 'unknown');
    });

    test('handles null recent_items gracefully', () {
      final json = {
        'name': 'Test',
        'type': 'rss',
        'url': 'https://test.com',
        'feed_url': 'https://test.com/feed',
        'recent_items': null,
      };

      final result = SmartSearchResult.fromJson(json);
      expect(result.recentItems, isEmpty);
    });

    test('handles malformed recent_items (string instead of list)', () {
      final json = {
        'name': 'Test',
        'type': 'rss',
        'url': 'https://test.com',
        'feed_url': 'https://test.com/feed',
        'recent_items': 'not a list',
      };

      final result = SmartSearchResult.fromJson(json);
      expect(result.recentItems, isEmpty);
    });
  });

  group('SmartSearchResponse.fromJson', () {
    test('parses complete response', () {
      final json = {
        'query_normalized': 'le monde',
        'results': [
          {
            'name': 'Le Monde',
            'type': 'article',
            'url': 'https://lemonde.fr',
            'feed_url': 'https://lemonde.fr/rss/une.xml',
          },
        ],
        'cache_hit': true,
        'layers_called': ['catalog', 'brave'],
        'latency_ms': 450,
      };

      final response = SmartSearchResponse.fromJson(json);

      expect(response.queryNormalized, 'le monde');
      expect(response.results, hasLength(1));
      expect(response.results[0].name, 'Le Monde');
      expect(response.cacheHit, true);
      expect(response.layersCalled, ['catalog', 'brave']);
      expect(response.latencyMs, 450);
    });

    test('handles empty response', () {
      final json = <String, dynamic>{};

      final response = SmartSearchResponse.fromJson(json);

      expect(response.queryNormalized, '');
      expect(response.results, isEmpty);
      expect(response.cacheHit, false);
      expect(response.layersCalled, isEmpty);
      expect(response.latencyMs, 0);
    });
  });
}
