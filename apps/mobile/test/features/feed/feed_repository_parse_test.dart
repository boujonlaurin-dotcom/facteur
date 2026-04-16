import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/feed/repositories/feed_repository.dart';

/// Regression tests for `FeedRepository.parseFeedData` — the static parsing
/// helper extracted from `getFeed` so the same path can also deserialize
/// cached payloads (Story 4.9).
///
/// The intent is to ensure the extraction did NOT change observable
/// behavior for the two payload shapes the backend can emit.
Map<String, dynamic> _validItem(String id) => {
      'id': id,
      'title': 'Title $id',
      'summary': '',
      'url': 'https://example.test/$id',
      'source': {
        'id': 'src-1',
        'name': 'Example',
        'logo_url': null,
        'theme': null,
      },
      'published_at': '2026-01-01T00:00:00Z',
      'content_type': 'article',
      'topics': <String>[],
      'entities': <Map<String, dynamic>>[],
    };

void main() {
  group('FeedRepository.parseFeedData — Map shape', () {
    test('parses items + pagination from the envelope', () {
      final data = <String, dynamic>{
        'items': [_validItem('a1'), _validItem('a2')],
        'pagination': {'has_next': true, 'total': 42},
      };

      final feed = FeedRepository.parseFeedData(data: data, page: 1, limit: 20);
      expect(feed.items.length, 2);
      expect(feed.items.first.id, 'a1');
      expect(feed.pagination.hasNext, true);
      expect(feed.pagination.total, 42);
      expect(feed.carousels, isEmpty);
    });

    test('tolerates a missing pagination block (falls back)', () {
      final data = <String, dynamic>{
        'items': [_validItem('a1')],
      };

      final feed = FeedRepository.parseFeedData(data: data, page: 1, limit: 20);
      expect(feed.items.length, 1);
      // parsePagination fallback: hasNext = itemsCount > 0
      expect(feed.pagination.hasNext, true);
    });

  });

  group('FeedRepository.parseFeedData — List shape (legacy)', () {
    test('parses a bare list of items', () {
      final data = [_validItem('a1'), _validItem('a2')];
      final feed = FeedRepository.parseFeedData(data: data, page: 1, limit: 20);
      expect(feed.items.length, 2);
      // Legacy shape: no pagination block → fallback hasNext = itemsCount > 0
      expect(feed.pagination.hasNext, true);
      expect(feed.pagination.total, 0);
    });

    test('returns empty state for an empty list', () {
      final feed =
          FeedRepository.parseFeedData(data: <dynamic>[], page: 1, limit: 20);
      expect(feed.items, isEmpty);
      expect(feed.pagination.hasNext, false);
    });
  });

  group('FeedRepository.parseFeedData — null / unexpected shapes', () {
    test('returns an empty response for null data', () {
      final feed = FeedRepository.parseFeedData(data: null, page: 1, limit: 20);
      expect(feed.items, isEmpty);
      expect(feed.carousels, isEmpty);
      expect(feed.pagination.hasNext, false);
    });
  });
}
