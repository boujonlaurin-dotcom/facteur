import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_state.dart';
import '../../flux_continu/providers/flux_continu_provider.dart';
import '../../flux_continu/services/flux_continu_cache_service.dart';
import '../models/content_model.dart';
import '../providers/feed_provider.dart';
import 'feed_cache_service.dart';

const articleReadThreshold = Duration(seconds: 1);

bool shouldCommitReadOnBackground({
  required DateTime startedAt,
  required DateTime now,
  required bool isConsumed,
  required bool isExternal,
}) {
  return !isConsumed &&
      !isExternal &&
      now.difference(startedAt) >= articleReadThreshold;
}

class PendingReadQueue {
  static const boxName = 'pending_reads';
  static const _keyPrefix = 'read:';

  final Box<String> box;

  PendingReadQueue(this.box);

  static PendingReadQueue? tryFromHive() {
    if (!Hive.isBoxOpen(boxName)) return null;
    return PendingReadQueue(Hive.box<String>(boxName));
  }

  String _key(String userId, String contentId) =>
      '$_keyPrefix$userId:$contentId';

  Future<void> enqueue(String userId, String contentId) async {
    await box.put(
      _key(userId, contentId),
      jsonEncode({
        'user_id': userId,
        'content_id': contentId,
        'queued_at': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }

  Map<String, String> pendingForUser(String userId) {
    final prefix = '$_keyPrefix$userId:';
    return {
      for (final key in box.keys.whereType<String>())
        if (key.startsWith(prefix)) key: key.substring(prefix.length),
    };
  }

  Future<void> remove(String key) => box.delete(key);

  Future<void> flushForUser(
    String userId, {
    required Future<void> Function(String contentId) sync,
    void Function(String contentId)? onPending,
  }) async {
    final entries = pendingForUser(userId);
    for (final entry in entries.entries) {
      onPending?.call(entry.value);
      try {
        await sync(entry.value);
        await remove(entry.key);
      } catch (_) {
        // Keep the durable entry for the next cold-start/foreground retry.
      }
    }
  }

  Future<void> clearForUser(String userId) async {
    final prefix = '$_keyPrefix$userId:';
    await box.deleteAll(
      box.keys.whereType<String>().where((key) => key.startsWith(prefix)),
    );
  }
}

final pendingReadQueueProvider = Provider<PendingReadQueue?>((ref) {
  return PendingReadQueue.tryFromHive();
});

final restoredReadSessionUserIdProvider = Provider<String?>((ref) {
  try {
    return Supabase.instance.client.auth.currentUser?.id;
  } catch (_) {
    return null;
  }
});

String? resolveReadSyncUserId(String? authUserId, String? restoredUserId) {
  return authUserId ?? restoredUserId;
}

final readSyncUserIdProvider = Provider<String?>((ref) {
  final authUserId = ref.watch(authStateProvider).user?.id;
  // Supabase restores its persisted session before AuthStateNotifier finishes
  // publishing it. The first article opened after launch must still be
  // enqueueable during that short window.
  return resolveReadSyncUserId(
    authUserId,
    ref.watch(restoredReadSessionUserIdProvider),
  );
});

final readSyncServiceProvider = Provider<ReadSyncService>((ref) {
  return ReadSyncService(ref);
});

final consumedContentIdsProvider = StateProvider<Set<String>>(
  (ref) => <String>{},
);

class ReadSyncService {
  final Ref ref;
  final void Function(String userId, String contentId)? propagateOverride;
  final Future<void> Function(String contentId)? syncOverride;
  final Set<String> _flushingUsers = <String>{};

  ReadSyncService(
    this.ref, {
    this.propagateOverride,
    this.syncOverride,
  });

  /// Returns true only after the durable queue entry has been written and the
  /// local state propagated. Network synchronization then continues
  /// asynchronously from that durable entry.
  Future<bool> markConsumed(String contentId) async {
    if (contentId.isEmpty) return false;
    final userId = ref.read(readSyncUserIdProvider);
    if (userId == null) {
      if (kDebugMode) {
        debugPrint('ReadSyncService: no restored user for $contentId');
      }
      return false;
    }
    final queue = ref.read(pendingReadQueueProvider);
    if (queue == null) {
      if (kDebugMode) {
        debugPrint('ReadSyncService: pending-read queue is not open');
      }
      return false;
    }

    // Durability first: an app kill after this await still leaves a retryable
    // record. UI state is then updated immediately, independently of network.
    await queue.enqueue(userId, contentId);
    _propagateLocal(userId, contentId);
    unawaited(flushForUser(userId, propagatePending: false));
    return true;
  }

  Future<void> flushCurrentUser() async {
    final userId = ref.read(readSyncUserIdProvider);
    if (userId != null) await flushForUser(userId);
  }

  Future<void> flushForUser(
    String userId, {
    bool propagatePending = true,
  }) async {
    final queue = ref.read(pendingReadQueueProvider);
    if (queue == null || !_flushingUsers.add(userId)) return;
    try {
      await queue.flushForUser(
        userId,
        onPending: propagatePending
            ? (contentId) => _propagateLocal(userId, contentId)
            : null,
        sync: (contentId) async {
          if (syncOverride != null) {
            await syncOverride!(contentId);
            return;
          }
          try {
            await ref
                .read(feedRepositoryProvider)
                .syncConsumedStatus(contentId);
          } catch (e) {
            if (kDebugMode) {
              debugPrint('ReadSyncService: flush failed for $contentId: $e');
            }
            rethrow;
          }
        },
      );
    } finally {
      _flushingUsers.remove(userId);
    }
  }

  void _propagateLocal(String userId, String contentId) {
    if (propagateOverride != null) {
      propagateOverride!(userId, contentId);
      return;
    }
    final consumedIds = ref.read(consumedContentIdsProvider.notifier);
    if (!consumedIds.state.contains(contentId)) {
      consumedIds.state = {...consumedIds.state, contentId};
    }
    ref.read(feedProvider.notifier).markContentConsumedLocally(contentId);
    ref.read(fluxContinuProvider.notifier).markArticleRead(contentId);

    final feedCache = ref.read(feedCacheServiceProvider);
    if (feedCache != null) {
      unawaited(
        feedCache.patchContentStatus(
          userId,
          contentId,
          ContentStatus.consumed,
          variant: FeedCacheVariant.normal,
        ),
      );
      unawaited(
        feedCache.patchContentStatus(
          userId,
          contentId,
          ContentStatus.consumed,
          variant: FeedCacheVariant.serein,
        ),
      );
    }
    unawaited(FluxContinuCacheService().patchContentConsumed(contentId));
  }
}
