import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_state.dart';
import '../../flux_continu/providers/flux_continu_provider.dart';
import '../../gamification/providers/streak_provider.dart';
import '../../flux_continu/services/flux_continu_cache_service.dart';
import '../models/content_model.dart';
import '../providers/feed_provider.dart';
import 'feed_cache_service.dart';

const articleReadThreshold = Duration(seconds: 1);

/// D'où vient le signal « lu jusqu'au bout ». Miroir de `CompletionSource`
/// côté backend.
enum CompletionSource {
  /// Contenu complet : bas de l'article atteint dans l'app.
  inApp('in_app'),

  /// Article trop court pour scroller.
  short('short'),

  /// Contenu partiel (~90 % du catalogue) : bas de la page atteint chez
  /// l'éditeur, via le pont JS de la WebView.
  web('web');

  const CompletionSource(this.wireValue);

  final String wireValue;

  static CompletionSource fromWire(String? value) {
    return CompletionSource.values.firstWhere(
      (s) => s.wireValue == value,
      orElse: () => CompletionSource.inApp,
    );
  }
}

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
  static const readPrefix = 'read:';

  /// Préfixe des lectures **abouties** (Epic 30). Même box Hive, autre espace
  /// de clés : la durabilité offline de la complétion est acquise sans
  /// migration ni nouvelle box.
  static const completionPrefix = 'done:';

  final Box<String> box;
  final String keyPrefix;

  PendingReadQueue(this.box, {this.keyPrefix = readPrefix});

  static PendingReadQueue? tryFromHive({String keyPrefix = readPrefix}) {
    if (!Hive.isBoxOpen(boxName)) return null;
    return PendingReadQueue(Hive.box<String>(boxName), keyPrefix: keyPrefix);
  }

  String _key(String userId, String contentId) =>
      '$keyPrefix$userId:$contentId';

  Future<void> enqueue(
    String userId,
    String contentId, {
    Map<String, dynamic>? extra,
  }) async {
    await box.put(
      _key(userId, contentId),
      jsonEncode({
        'user_id': userId,
        'content_id': contentId,
        'queued_at': DateTime.now().toUtc().toIso8601String(),
        ...?extra,
      }),
    );
  }

  /// Payload durable d'une entrée, ou `null` si elle n'existe plus.
  /// Permet au flush de récupérer un champ (ex. `completion_source`) que la
  /// callback `sync` ne reçoit pas.
  Map<String, dynamic>? payloadFor(String userId, String contentId) {
    final raw = box.get(_key(userId, contentId));
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Map<String, String> pendingForUser(String userId) {
    final prefix = '$keyPrefix$userId:';
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
    final prefix = '$keyPrefix$userId:';
    await box.deleteAll(
      box.keys.whereType<String>().where((key) => key.startsWith(prefix)),
    );
  }
}

final pendingReadQueueProvider = Provider<PendingReadQueue?>((ref) {
  return PendingReadQueue.tryFromHive();
});

final pendingCompletionQueueProvider = Provider<PendingReadQueue?>((ref) {
  return PendingReadQueue.tryFromHive(
    keyPrefix: PendingReadQueue.completionPrefix,
  );
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

/// Articles lus **jusqu'au bout** pendant la session — permet aux cartes de
/// refléter la complétion sans attendre un refetch.
final completedContentIdsProvider = StateProvider<Set<String>>(
  (ref) => <String>{},
);

class ReadSyncService {
  final Ref ref;
  final void Function(String userId, String contentId)? propagateOverride;
  final Future<void> Function(String contentId)? syncOverride;
  final Future<void> Function(String contentId, CompletionSource source)?
      completionSyncOverride;
  final Set<String> _flushingUsers = <String>{};
  final Set<String> _flushingCompletionUsers = <String>{};

  ReadSyncService(
    this.ref, {
    this.propagateOverride,
    this.syncOverride,
    this.completionSyncOverride,
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

  /// Enregistre « lu jusqu'au bout ».
  ///
  /// Même ordre que [markConsumed] : **durabilité d'abord**, puis état local,
  /// puis réseau — une complétion dans le métro ne doit pas être perdue, sinon
  /// le compteur du jour est faux et visiblement injuste.
  ///
  /// Requête distincte de celle du statut `consumed` : les combiner ferait
  /// perdre `completed_at` (garde d'idempotence côté serveur).
  Future<bool> markCompleted(String contentId, CompletionSource source) async {
    if (contentId.isEmpty) return false;
    final userId = ref.read(readSyncUserIdProvider);
    if (userId == null) return false;
    final queue = ref.read(pendingCompletionQueueProvider);
    if (queue == null) return false;

    final completedIds = ref.read(completedContentIdsProvider.notifier);
    if (completedIds.state.contains(contentId)) return false;

    await queue.enqueue(userId, contentId, extra: {'source': source.wireValue});
    completedIds.state = {...completedIds.state, contentId};
    unawaited(flushCompletionsForUser(userId));
    return true;
  }

  Future<void> flushCompletionsForUser(String userId) async {
    final queue = ref.read(pendingCompletionQueueProvider);
    if (queue == null || !_flushingCompletionUsers.add(userId)) return;
    final hadPending = queue.pendingForUser(userId).isNotEmpty;
    try {
      await queue.flushForUser(
        userId,
        sync: (contentId) async {
          final source = CompletionSource.fromWire(
            queue.payloadFor(userId, contentId)?['source'] as String?,
          );
          if (completionSyncOverride != null) {
            await completionSyncOverride!(contentId, source);
            return;
          }
          await ref
              .read(feedRepositoryProvider)
              .markContentCompleted(contentId, source);
        },
      );
    } finally {
      _flushingCompletionUsers.remove(userId);
    }
    // Le compteur du jour est dérivé côté serveur : on le relit une fois la
    // complétion confirmée, plutôt que de tenir un compteur local qui
    // divergerait.
    if (hadPending) {
      unawaited(ref.read(streakProvider.notifier).refreshSilent());
    }
  }

  Future<void> flushCurrentUser() async {
    final userId = ref.read(readSyncUserIdProvider);
    if (userId == null) return;
    await flushForUser(userId);
    await flushCompletionsForUser(userId);
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
