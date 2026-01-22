import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/feed/models/content_model.dart';

void main() {
  group('Defensive JSON Parsing (G5)', () {
    test(
        'Content.fromJson should handle malformed source (Map expected, List received) without crashing',
        () {
      final malformedJson = {
        'id': 'test-id',
        'title': 'Test Title',
        'url': 'https://example.com',
        'content_type': 'article',
        'published_at': '2024-01-22T08:00:00Z',
        'source': ['this', 'should', 'be', 'a', 'map'], // Mismatch!
        'status': 'unseen',
      };

      final content = Content.fromJson(malformedJson);

      expect(content.id, equals('test-id'));
      expect(content.source.name, equals('Source Inconnue')); // Fallback used
      expect(content.source.id, equals('fallback'));
    });

    test(
        'RecommendationReason.fromJson should handle malformed breakdown (List expected, Map received) without crashing',
        () {
      final malformedJson = {
        'label': 'Test Label',
        'score_total': 100.0,
        'breakdown': {'should': 'be', 'a': 'list'}, // Mismatch!
      };

      final reason = RecommendationReason.fromJson(malformedJson);

      expect(reason.label, equals('Test Label'));
      expect(reason.breakdown, isEmpty); // Fallback to empty list
    });

    test(
        'Content.fromJson should handle totally garbage recommendation_reason without crashing',
        () {
      final malformedJson = {
        'id': 'test-id',
        'title': 'Test Title',
        'url': 'https://example.com',
        'content_type': 'article',
        'published_at': '2024-01-22T08:00:00Z',
        'source': {
          'id': 'source-id',
          'name': 'Source Name',
          'type': 'article',
        },
        'recommendation_reason': 'Not a map at all', // Mismatch!
      };

      final content = Content.fromJson(malformedJson);

      expect(content.id, equals('test-id'));
      expect(content.recommendationReason, isNull);
    });

    test('Content.fromJson should handle invalid date format gracefully', () {
      final malformedJson = {
        'id': 'test-id',
        'title': 'Test Title',
        'url': 'https://example.com',
        'content_type': 'article',
        'published_at': 'garbage-date', // Invalid format
        'source': {
          'id': 'source-id',
          'name': 'Source Name',
          'type': 'article',
        },
      };

      final content = Content.fromJson(malformedJson);

      expect(content.id, equals('test-id'));
      // Should fallback to DateTime.now() instead of crashing
      expect(content.publishedAt, isNotNull);
    });
  });
}
