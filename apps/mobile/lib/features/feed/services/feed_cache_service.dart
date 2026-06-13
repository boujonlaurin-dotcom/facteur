import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/content_model.dart';

enum FeedCacheVariant { normal, serein }

/// Local cache for the "default" feed (page 1, no filters) to enable
/// stale-while-revalidate UX: instant paint on cold open + silent refetch.
///
/// Storage: Hive `Box<String>` named `feed_cache` (opened in `main.dart`).
/// Key shape: `feed:{userId}:normal` / `feed:{userId}:serein`.
/// Legacy normal entries at `feed:{userId}` are still readable.
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

  String _legacyKey(String userId) => 'feed:$userId';

  String _key(String userId, FeedCacheVariant variant) =>
      'feed:$userId:${variant.name}';

  /// Persist a raw feed response (decoded JSON) for [userId].
  ///
  /// The caller should only invoke this for page 1 with no filters active
  /// (default feed). No-op on serialization error.
  Future<void> saveRaw(
    String userId,
    dynamic rawData, {
    FeedCacheVariant variant = FeedCacheVariant.normal,
  }) async {
    try {
      final payload = <String, dynamic>{
        'saved_at': DateTime.now().millisecondsSinceEpoch,
        'data': rawData,
      };
      await _box.put(_key(userId, variant), jsonEncode(payload));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('FeedCacheService.saveRaw failed: $e');
      }
    }
  }

  /// Read the cached raw feed response for [userId], or null if absent /
  /// corrupted. A corrupted entry is evicted on read.
  CachedFeedRaw? readRaw(
    String userId, {
    FeedCacheVariant variant = FeedCacheVariant.normal,
  }) {
    final entry = _readEncoded(userId, variant);
    if (entry == null) return null;
    final (key, encoded) = entry;
    return _decodeEntry(key, encoded);
  }

  (String, String)? _readEncoded(String userId, FeedCacheVariant variant) {
    final key = _key(userId, variant);
    final encoded = _box.get(key);
    if (encoded != null) return (key, encoded);
    if (variant == FeedCacheVariant.normal) {
      final legacyKey = _legacyKey(userId);
      final legacy = _box.get(legacyKey);
      if (legacy != null) return (legacyKey, legacy);
    }
    return null;
  }

  CachedFeedRaw? _decodeEntry(String key, String encoded) {
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

  /// Patch a single content status inside a cached raw payload.
  ///
  /// Supports the two raw shapes used by `FeedRepository.parseFeedData`:
  /// a top-level List of content maps, or a Map with `items` and optional
  /// `carousels[].items`. Returns false if no matching content exists or the
  /// entry cannot be decoded.
  Future<bool> patchContentStatus(
    String userId,
    String contentId,
    ContentStatus status, {
    FeedCacheVariant variant = FeedCacheVariant.normal,
  }) async {
    final entry = _readEncoded(userId, variant);
    if (entry == null) return false;
    final (key, encoded) = entry;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) {
        await _box.delete(key);
        return false;
      }
      final savedAt = decoded['saved_at'];
      final data = decoded['data'];
      if (savedAt is! int || data == null) {
        await _box.delete(key);
        return false;
      }
      final patched = _patchStatusInData(data, contentId, status.name);
      if (!patched) return false;
      await _box.put(key, jsonEncode(decoded));
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('FeedCacheService.patchContentStatus failed: $e');
      }
      await _box.delete(key);
      return false;
    }
  }

  bool _patchStatusInData(dynamic data, String contentId, String status) {
    var patched = false;

    bool patchItem(dynamic item) {
      if (item is! Map<String, dynamic>) return false;
      if (item['id'] != contentId) return false;
      item['status'] = status;
      return true;
    }

    if (data is List) {
      for (final item in data) {
        patched = patchItem(item) || patched;
      }
      return patched;
    }

    if (data is Map<String, dynamic>) {
      final items = data['items'];
      if (items is List) {
        for (final item in items) {
          patched = patchItem(item) || patched;
        }
      }

      final carousels = data['carousels'];
      if (carousels is List) {
        for (final carousel in carousels) {
          if (carousel is! Map<String, dynamic>) continue;
          final carouselItems = carousel['items'];
          if (carouselItems is! List) continue;
          for (final item in carouselItems) {
            patched = patchItem(item) || patched;
          }
        }
      }
    }

    return patched;
  }

  /// Remove cache entries for [userId]. Use on logout or user switch.
  Future<void> clearForUser(String userId, {FeedCacheVariant? variant}) async {
    if (variant != null) {
      await _box.delete(_key(userId, variant));
      if (variant == FeedCacheVariant.normal) {
        await _box.delete(_legacyKey(userId));
      }
      return;
    }
    await _box.deleteAll([
      _key(userId, FeedCacheVariant.normal),
      _key(userId, FeedCacheVariant.serein),
      _legacyKey(userId),
    ]);
  }

  /// Wipe every cache entry. Use on global reset.
  Future<void> clearAll() async {
    await _box.clear();
  }

  /// Whether [savedAt] is within the [ttl] window from [now].
  static bool isFresh(
    DateTime savedAt, {
    DateTime? now,
    Duration ttl = defaultTtl,
  }) {
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
