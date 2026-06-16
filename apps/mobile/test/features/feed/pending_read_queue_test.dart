import 'dart:io';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:facteur/features/feed/services/read_sync_service.dart';

void main() {
  late Directory tempDir;
  late Box<String> box;
  late PendingReadQueue queue;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('pending_reads_test_');
    Hive.init(tempDir.path);
    box = await Hive.openBox<String>(PendingReadQueue.boxName);
  });

  setUp(() async {
    await box.clear();
    queue = PendingReadQueue(box);
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('entry exists before sync and is removed after success', () async {
    await queue.enqueue('user-1', 'article-1');

    await queue.flushForUser(
      'user-1',
      sync: (contentId) async {
        expect(contentId, 'article-1');
        expect(queue.pendingForUser('user-1').values, contains(contentId));
      },
    );

    expect(queue.pendingForUser('user-1'), isEmpty);
  });

  test('failed sync keeps entry until a later successful retry', () async {
    await queue.enqueue('user-1', 'article-1');

    await queue.flushForUser(
      'user-1',
      sync: (_) async => throw StateError('offline'),
    );
    expect(queue.pendingForUser('user-1').values, contains('article-1'));

    await queue.flushForUser('user-1', sync: (_) async {});
    expect(queue.pendingForUser('user-1'), isEmpty);
  });

  test('flush and cleanup are isolated by user', () async {
    await queue.enqueue('user-1', 'article-1');
    await queue.enqueue('user-2', 'article-2');

    await queue.flushForUser('user-1', sync: (_) async {});

    expect(queue.pendingForUser('user-1'), isEmpty);
    expect(queue.pendingForUser('user-2').values, contains('article-2'));

    await queue.clearForUser('user-2');
    expect(queue.pendingForUser('user-2'), isEmpty);
  });

  test('background commits only once the one-second threshold is reached', () {
    final startedAt = DateTime.utc(2026, 6, 10, 10);

    expect(
      shouldCommitReadOnBackground(
        startedAt: startedAt,
        now: startedAt.add(const Duration(milliseconds: 999)),
        isConsumed: false,
        isExternal: false,
      ),
      isFalse,
    );
    expect(
      shouldCommitReadOnBackground(
        startedAt: startedAt,
        now: startedAt.add(const Duration(seconds: 1)),
        isConsumed: false,
        isExternal: false,
      ),
      isTrue,
    );
  });

  test('restored session user is used before auth state is published', () {
    expect(resolveReadSyncUserId(null, 'restored-user'), 'restored-user');
    expect(resolveReadSyncUserId('auth-user', 'restored-user'), 'auth-user');
  });

  test('mark succeeds only after enqueue, then flushes asynchronously',
      () async {
    final events = <String>[];
    final syncGate = Completer<void>();
    late ProviderContainer container;
    final serviceProvider = Provider<ReadSyncService>((ref) {
      return ReadSyncService(
        ref,
        propagateOverride: (userId, contentId) {
          events.add('propagate');
          expect(queue.pendingForUser(userId).values, contains(contentId));
        },
        syncOverride: (contentId) async {
          events.add('sync');
          expect(queue.pendingForUser('user-1').values, contains(contentId));
          await syncGate.future;
        },
      );
    });
    container = ProviderContainer(
      overrides: [
        pendingReadQueueProvider.overrideWithValue(queue),
        readSyncUserIdProvider.overrideWithValue('user-1'),
      ],
    );
    addTearDown(container.dispose);

    final marked =
        await container.read(serviceProvider).markConsumed('article-1');

    expect(marked, isTrue);
    expect(events, ['propagate', 'sync']);
    expect(queue.pendingForUser('user-1').values, contains('article-1'));

    syncGate.complete();
    for (var i = 0; i < 20 && queue.pendingForUser('user-1').isNotEmpty; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(queue.pendingForUser('user-1'), isEmpty);
  });

  test('mark stays retryable when user or queue is unavailable', () async {
    final noUserContainer = ProviderContainer(
      overrides: [
        pendingReadQueueProvider.overrideWithValue(queue),
        readSyncUserIdProvider.overrideWithValue(null),
      ],
    );
    addTearDown(noUserContainer.dispose);
    expect(
      await noUserContainer
          .read(readSyncServiceProvider)
          .markConsumed('article-1'),
      isFalse,
    );

    final noQueueContainer = ProviderContainer(
      overrides: [
        pendingReadQueueProvider.overrideWithValue(null),
        readSyncUserIdProvider.overrideWithValue('user-1'),
      ],
    );
    addTearDown(noQueueContainer.dispose);
    expect(
      await noQueueContainer
          .read(readSyncServiceProvider)
          .markConsumed('article-1'),
      isFalse,
    );
    expect(queue.pendingForUser('user-1'), isEmpty);
  });
}
