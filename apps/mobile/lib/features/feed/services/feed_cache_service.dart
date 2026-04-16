import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Local cache for the "default" feed (page 1, no filters) to enable
/// stale-while-revalidate UX: instant paint on cold open + silent refetch.
///
/// Storage: Hive `Box<String>` named `feed_cache` (opened in `main.dart`).
/// Key shape: `feed:{userId}`.
/// Value shape: JSON string `{"saved_at": <ms>, "data": <raw API response>}`.
///
/// Why cache the raw API response (not a parsed model):
/// the feed models (`Content`, `Source`, `FeedCluster`, …) have no `toJson`.
/// Persisting the decoded Map/List returned by Dio and piping it back through
/// the existing `FeedRepository.parseFeedData` avoids duplicating parsing
/// logic and keeps the cache auto-valid across schema evolutions.
///
/// A corrupted entry (invalid JSON, schema drift causing parse failure)
/// is silently dropped — see [readRaw] and [FeedCacheService]'s callers.
class FeedCacheService {
  static const String boxName = 'feed_cache';

  /// Cache freshness window. Entries older than this are considered stale
  /// (caller still gets the stale value if it asks, but the typical flow is
  /// to check [isFresh] first).
  static const Duration defaultTtl = Duration(minutes: 10);

  final Box<String> _box;

  FeedCacheService(this._box);

  /// Construct the service from the globally-opened Hive box.
  /// Returns null if the box was never opened (tests without Hive init).
  static FeedCacheService? tryFromHive() {
    if (!Hive.isBoxOpen(boxName)) return null;
    return FeedCacheService(Hive.box<String>(boxName));
  }

  String _key(String userId) => 'feed:$userId';

  /// Persist a raw feed response (decoded JSON) for [userId].
  ///
  /// The caller should only invoke this for page 1 with no filters active
  /// (default feed). No-op on serialization error.
  Future<void> saveRaw(String userId, dynamic rawData) async {
    try {
      final payload = <String, dynamic>{
        'saved_at': DateTime.now().millisecondsSinceEpoch,
        'data': rawData,
      };
      await _box.put(_key(userId), jsonEncode(payload));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('FeedCacheService.saveRaw failed: $e');
      }
    }
  }

  /// Read the cached raw feed response for [userId], or null if absent /
  /// corrupted. A corrupted entry is evicted on read.
  CachedFeedRaw? readRaw(String userId) {
    final key = _key(userId);
    final encoded = _box.get(key);
    if (encoded == null) return null;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) {
        _box.delete(key);
        return null;
      }
      final savedAt = decoded['saved_at'];
      final data = decoded['data'];
      if (savedAt is! int || data == null) {
        _box.delete(key);
        return null;
      }
      return CachedFeedRaw(
        savedAt: DateTime.fromMillisecondsSinceEpoch(savedAt),
        data: data,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('FeedCacheService.readRaw corrupted, evicting: $e');
      }
      _box.delete(key);
      return null;
    }
  }

  /// Remove the cache entry for [userId]. Use on logout or user switch.
  Future<void> clearForUser(String userId) async {
    await _box.delete(_key(userId));
  }

  /// Wipe every cache entry. Use on global reset.
  Future<void> clearAll() async {
    await _box.clear();
  }

  /// Whether [savedAt] is within the [ttl] window from [now].
  static bool isFresh(DateTime savedAt,
      {DateTime? now, Duration ttl = defaultTtl}) {
    final reference = now ?? DateTime.now();
    return reference.difference(savedAt) < ttl;
  }
}

/// Immutable snapshot of a cached feed entry.
class CachedFeedRaw {
  final DateTime savedAt;

  /// Raw decoded JSON payload (Map or List), ready to be piped into
  /// `FeedRepository.parseFeedData`.
  final dynamic data;

  const CachedFeedRaw({required this.savedAt, required this.data});

  bool get isFresh => FeedCacheService.isFresh(savedAt);
}
