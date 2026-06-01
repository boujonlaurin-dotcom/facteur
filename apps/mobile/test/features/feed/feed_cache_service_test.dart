import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/feed/services/feed_cache_service.dart';

/// Unit tests for FeedCacheService — the Hive-backed local cache powering
/// the stale-while-revalidate feed load (Story 4.9).
///
/// The service should:
/// - round-trip arbitrary JSON-serializable payloads (raw API shape)
/// - return null for missing users (never serve another user's cache)
/// - detect freshness via `isFresh` with a configurable TTL
/// - silently evict corrupted entries instead of crashing
void main() {
  late Directory tempDir;
  late Box<String> box;
  late FeedCacheService service;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('feed_cache_test_');
    Hive.init(tempDir.path);
    box = await Hive.openBox<String>(FeedCacheService.boxName);
  });

  setUp(() async {
    await box.clear();
    service = FeedCacheService(box);
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  group('FeedCacheService.saveRaw / readRaw', () {
    test('round-trips a Map payload', () async {
      const userId = 'user-1';
      final payload = <String, dynamic>{
        'items': [
          {'id': 'a1', 'title': 'Hello'},
          {'id': 'a2', 'title': 'World'},
        ],
        'pagination': {'has_next': true, 'total': 42},
      };

      await service.saveRaw(userId, payload);
      final cached = service.readRaw(userId);

      expect(cached, isNotNull);
      expect(cached!.data, isA<Map<String, dynamic>>());
      expect((cached.data as Map)['pagination']['total'], 42);
      expect(((cached.data as Map)['items'] as List).length, 2);
    });

    test('round-trips a List payload (legacy shape)', () async {
      const userId = 'user-2';
      final payload = <Map<String, dynamic>>[
        {'id': 'a1'},
        {'id': 'a2'},
      ];

      await service.saveRaw(userId, payload);
      final cached = service.readRaw(userId);

      expect(cached, isNotNull);
      expect(cached!.data, isA<List<dynamic>>());
      expect((cached.data as List<dynamic>).length, 2);
    });

    test('reads are user-scoped: another user sees null', () async {
      await service.saveRaw('user-A', {'items': <dynamic>[]});
      expect(service.readRaw('user-B'), isNull);
    });

    test('keeps normal and serein variants separated', () async {
      await service.saveRaw('user-mode', {
        'items': <Map<String, dynamic>>[
          {'id': 'normal'},
        ],
      });
      await service.saveRaw(
          'user-mode',
          {
            'items': <Map<String, dynamic>>[
              {'id': 'serein'},
            ],
          },
          variant: FeedCacheVariant.serein);

      final normal = service.readRaw('user-mode')!.data as Map;
      final serein = service
          .readRaw('user-mode', variant: FeedCacheVariant.serein)!
          .data as Map;

      expect((normal['items'] as List).first['id'], 'normal');
      expect((serein['items'] as List).first['id'], 'serein');
    });

    test('normal reads fall back to legacy feed:userId key', () async {
      await box.put(
        'feed:legacy-user',
        '{"saved_at":1760000000000,"data":{"items":[{"id":"legacy"}]}}',
      );

      final cached = service.readRaw('legacy-user');

      expect(cached, isNotNull);
      expect(((cached!.data as Map)['items'] as List).first['id'], 'legacy');
    });

    test('returns null when nothing has been saved', () {
      expect(service.readRaw('never-seen'), isNull);
    });
  });

  group('FeedCacheService.patchContentStatus', () {
    test('patches top-level List payloads', () async {
      await service.saveRaw('user-list', [
        {'id': 'a1', 'status': 'unseen'},
        {'id': 'a2', 'status': 'unseen'},
      ]);

      final patched = await service.patchContentStatus(
        'user-list',
        'a2',
        ContentStatus.consumed,
      );
      final data = service.readRaw('user-list')!.data as List;

      expect(patched, isTrue);
      expect(data[0]['status'], 'unseen');
      expect(data[1]['status'], 'consumed');
    });

    test('patches Map items and carousel items', () async {
      await service.saveRaw('user-map', {
        'items': [
          {'id': 'a1', 'status': 'unseen'},
        ],
        'carousels': [
          {
            'items': [
              {'id': 'a2', 'status': 'unseen'},
            ],
          },
        ],
      });

      final patched = await service.patchContentStatus(
        'user-map',
        'a2',
        ContentStatus.consumed,
      );
      final data = service.readRaw('user-map')!.data as Map;
      final carouselItems =
          ((data['carousels'] as List).first as Map)['items'] as List;

      expect(patched, isTrue);
      expect((data['items'] as List).first['status'], 'unseen');
      expect(carouselItems.first['status'], 'consumed');
    });

    test('returns false without clearing when content is absent', () async {
      await service.saveRaw('user-absent', {
        'items': [
          {'id': 'a1', 'status': 'unseen'},
        ],
      });

      final patched = await service.patchContentStatus(
        'user-absent',
        'missing',
        ContentStatus.consumed,
      );

      expect(patched, isFalse);
      expect(service.readRaw('user-absent'), isNotNull);
    });
  });

  group('FeedCacheService.isFresh', () {
    test('returns true within the TTL window', () {
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      final savedAt = now.subtract(const Duration(minutes: 5));
      expect(FeedCacheService.isFresh(savedAt, now: now), isTrue);
    });

    test('returns false past the TTL window', () {
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      final savedAt = now.subtract(const Duration(minutes: 15));
      expect(FeedCacheService.isFresh(savedAt, now: now), isFalse);
    });

    test('accepts a custom TTL', () {
      final now = DateTime(2026, 1, 1, 12, 0, 0);
      final savedAt = now.subtract(const Duration(seconds: 30));
      expect(
        FeedCacheService.isFresh(
          savedAt,
          now: now,
          ttl: const Duration(seconds: 10),
        ),
        isFalse,
      );
      expect(
        FeedCacheService.isFresh(
          savedAt,
          now: now,
          ttl: const Duration(minutes: 1),
        ),
        isTrue,
      );
    });

    test('cached.isFresh flag reflects recent save', () async {
      await service.saveRaw('user-fresh', {'items': <dynamic>[]});
      final cached = service.readRaw('user-fresh');
      expect(cached!.isFresh, isTrue);
    });
  });

  group('FeedCacheService — corruption + invalidation', () {
    test('silently evicts a corrupted entry and returns null', () async {
      const userId = 'user-corrupt';
      // Write a raw non-JSON string directly into the box to simulate a
      // disk-level corruption / schema mismatch.
      await box.put('feed:$userId', '{not valid json at all');

      final cached = service.readRaw(userId);
      expect(cached, isNull);
      // The corrupted entry must have been wiped, not left to poison
      // subsequent reads.
      expect(box.get('feed:$userId'), isNull);
    });

    test('evicts entries with a missing savedAt field', () async {
      const userId = 'user-partial';
      // Missing `saved_at` on purpose.
      await box.put('feed:$userId', '{"data":{"items":[]}}');
      expect(service.readRaw(userId), isNull);
      expect(box.get('feed:$userId'), isNull);
    });

    test('clearForUser removes only that user\'s entry', () async {
      await service.saveRaw('keep-me', {
        'items': [1],
      });
      await service.saveRaw('drop-me', {
        'items': [2],
      });

      await service.clearForUser('drop-me');

      expect(service.readRaw('keep-me'), isNotNull);
      expect(service.readRaw('drop-me'), isNull);
    });

    test('clearAll wipes every entry', () async {
      await service.saveRaw('user-a', {'items': <dynamic>[]});
      await service.saveRaw('user-b', {'items': <dynamic>[]});
      await service.clearAll();
      expect(service.readRaw('user-a'), isNull);
      expect(service.readRaw('user-b'), isNull);
    });
  });
}
