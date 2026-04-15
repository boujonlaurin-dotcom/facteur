import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/feed/repositories/feed_repository.dart';

/// Unit tests for FeedRepository.parsePagination.
///
/// Covers the hybrid pagination logic introduced to fix the feed infinite-scroll
/// regression: the backend now emits a `pagination` block (based on the
/// pre-diversification candidate pool) but older responses — and non-feed
/// proxies — still return a raw JSON list.
void main() {
  group('FeedRepository.parsePagination — backend Map shape', () {
    test('reads has_next and total when both are present', () {
      final data = {
        'items': [],
        'pagination': {'has_next': true, 'total': 42},
      };

      final p = FeedRepository.parsePagination(
        data: data,
        page: 1,
        limit: 20,
        itemsCount: 18,
      );

      expect(p.page, 1);
      expect(p.perPage, 20);
      expect(p.total, 42);
      expect(p.hasNext, true);
    });

    test('trusts has_next=false even when items are present', () {
      // Regression guard: the backend knows the pool is exhausted even if the
      // page came back full (e.g. exactly `limit` items remaining).
      final data = {
        'items': List.generate(20, (i) => {'id': '$i'}),
        'pagination': {'has_next': false, 'total': 20},
      };

      final p = FeedRepository.parsePagination(
        data: data,
        page: 1,
        limit: 20,
        itemsCount: 20,
      );

      expect(p.hasNext, false);
      expect(p.total, 20);
    });

    test('trusts has_next=true even when items came back empty', () {
      // The provider layer is responsible for the safety net
      // (`hasNext && items.isNotEmpty`). The repository simply mirrors the
      // backend.
      final data = {
        'items': [],
        'pagination': {'has_next': true, 'total': 100},
      };

      final p = FeedRepository.parsePagination(
        data: data,
        page: 3,
        limit: 20,
        itemsCount: 0,
      );

      expect(p.hasNext, true);
      expect(p.total, 100);
    });
  });

  group('FeedRepository.parsePagination — missing/invalid backend metadata', () {
    test('falls back to itemsCount > 0 when pagination is missing', () {
      final data = {'items': []};

      final emptyPage = FeedRepository.parsePagination(
        data: data,
        page: 2,
        limit: 20,
        itemsCount: 0,
      );
      expect(emptyPage.hasNext, false);
      expect(emptyPage.total, 0);

      final nonEmptyPage = FeedRepository.parsePagination(
        data: {'items': []},
        page: 1,
        limit: 20,
        itemsCount: 10,
      );
      expect(nonEmptyPage.hasNext, true);
      expect(nonEmptyPage.total, 0);
    });

    test('falls back to itemsCount when pagination block is malformed', () {
      final data = {
        'pagination': 'not-a-map',
      };

      final p = FeedRepository.parsePagination(
        data: data,
        page: 1,
        limit: 20,
        itemsCount: 5,
      );

      expect(p.hasNext, true); // itemsCount > 0
      expect(p.total, 0);
    });

    test('ignores non-bool has_next and non-int total', () {
      final data = {
        'pagination': {'has_next': 'yes', 'total': '42'},
      };

      final p = FeedRepository.parsePagination(
        data: data,
        page: 1,
        limit: 20,
        itemsCount: 3,
      );

      expect(p.hasNext, true); // fallback to itemsCount > 0
      expect(p.total, 0); // fallback default
    });

    test('partial pagination metadata: only has_next', () {
      final data = {
        'pagination': {'has_next': false},
      };

      final p = FeedRepository.parsePagination(
        data: data,
        page: 1,
        limit: 20,
        itemsCount: 5,
      );

      expect(p.hasNext, false);
      expect(p.total, 0);
    });

    test('partial pagination metadata: only total', () {
      final data = {
        'pagination': {'total': 99},
      };

      final p = FeedRepository.parsePagination(
        data: data,
        page: 1,
        limit: 20,
        itemsCount: 7,
      );

      expect(p.hasNext, true); // fallback (itemsCount > 0)
      expect(p.total, 99);
    });
  });

  group('FeedRepository.parsePagination — legacy List response shape', () {
    test('returns hasNext=itemsCount>0 and total=0 for a raw List', () {
      final List<dynamic> data = [
        {'id': 'a'},
        {'id': 'b'},
      ];

      final p = FeedRepository.parsePagination(
        data: data,
        page: 1,
        limit: 20,
        itemsCount: 2,
      );

      expect(p.hasNext, true);
      expect(p.total, 0);
    });

    test('empty list returns hasNext=false', () {
      final List<dynamic> data = [];

      final p = FeedRepository.parsePagination(
        data: data,
        page: 5,
        limit: 20,
        itemsCount: 0,
      );

      expect(p.hasNext, false);
      expect(p.total, 0);
    });
  });

  group('FeedRepository.parsePagination — defensive', () {
    test('null data falls back to itemsCount-based inference', () {
      final p = FeedRepository.parsePagination(
        data: null,
        page: 1,
        limit: 20,
        itemsCount: 0,
      );

      expect(p.hasNext, false);
      expect(p.total, 0);
    });

    test('page and perPage are propagated as-is', () {
      final p = FeedRepository.parsePagination(
        data: null,
        page: 7,
        limit: 50,
        itemsCount: 1,
      );

      expect(p.page, 7);
      expect(p.perPage, 50);
    });
  });
}
