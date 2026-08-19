import 'dart:async';
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

  /// Préfixe des entrées **section de la Tournée** (SWR in-day). Une entrée
  /// **par section** (jamais un map imbriqué) : le patch « article lu » au
  /// retour de WebView ne doit jamais décoder l'ensemble du cache sur le thread
  /// UI — c'est le piège que porte déjà `FluxContinuCacheService`
  /// (`patchContentConsumed` walk le snapshot entier).
  /// Clé : `tournee:{userId}:{variant}:{sectionKey}`.
  /// Valeur : `{"saved_at": ms, "day_key": "AAAA-MM-JJ", "header": {…},
  /// "data": raw API}` — même principe que les entrées feed (on persiste le
  /// brut, les modèles feed n'ayant pas de `toJson`), plus l'en-tête d'affichage
  /// de la section pour pouvoir la rendre sans le catalogue sources.
  static const String tourneePrefix = 'tournee:';

  String _legacyKey(String userId) => 'feed:$userId';

  String _key(String userId, FeedCacheVariant variant) =>
      'feed:$userId:${variant.name}';

  String _tourneeUserPrefix(String userId) => '$tourneePrefix$userId:';

  String _tourneeKey(String userId, FeedCacheVariant variant, String section) =>
      '${_tourneeUserPrefix(userId)}${variant.name}:$section';

  List<String> _tourneeKeysForUser(String userId) {
    final prefix = _tourneeUserPrefix(userId);
    return [
      for (final key in _box.keys)
        if (key is String && key.startsWith(prefix)) key,
    ];
  }

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

  /// Persiste une **section de la Tournée** (SWR in-day) : en-tête d'affichage
  /// + payload brut, daté par [dayKey] (jour éditorial, pas un TTL glissant :
  /// la Tournée est une édition du jour).
  ///
  /// L'appelant ne doit jamais persister une section **vide** : côté veille,
  /// `getVeilleFeedItems` avale les DioException et renvoie un feed vide — on
  /// mémoriserait une panne réseau comme un contenu légitime (fail-closed).
  Future<void> saveTourneeSection(
    String userId,
    String section, {
    required FeedCacheVariant variant,
    required String dayKey,
    required Map<String, dynamic> header,
    required dynamic rawData,
  }) async {
    try {
      final payload = <String, dynamic>{
        'saved_at': DateTime.now().millisecondsSinceEpoch,
        'day_key': dayKey,
        'header': header,
        'data': rawData,
      };
      await _box.put(
        _tourneeKey(userId, variant, section),
        jsonEncode(payload),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('FeedCacheService.saveTourneeSection failed: $e');
      }
    }
  }

  /// Sections de la Tournée persistées **pour [dayKey]** et [variant], clés par
  /// `sectionKey`. Purge au passage, toutes variantes confondues, ce qui date
  /// d'une autre édition ou ne se relit pas (une seule passe sur les clés
  /// plutôt qu'un balayage de purge séparé).
  ///
  /// Appelée **sur le chemin de peinture du boot** : le tri jour/variante se
  /// fait donc sans jamais `jsonDecode` une entrée qu'on ne rendra pas — le
  /// `day_key` est cherché dans la **chaîne encodée** (`{"saved_at":…,
  /// "day_key":"AAAA-MM-JJ",…}`, même pré-filtre que
  /// [patchTourneeContentStatus]), et la variante dans le nom de la clé. Sans
  /// ça, un utilisateur ayant basculé en mode serein dans la journée paierait
  /// au boot le décodage de ses ~10 sections de l'autre mode, sur le thread UI
  /// — exactement le coût que ce lot cherche à supprimer.
  Map<String, CachedTourneeSection> readTourneeSectionsForToday(
    String userId, {
    required FeedCacheVariant variant,
    required String dayKey,
  }) {
    final result = <String, CachedTourneeSection>{};
    final stale = <String>[];
    final dayMarker = '"day_key":"$dayKey"';
    final variantPrefix = '${_tourneeUserPrefix(userId)}${variant.name}:';
    for (final key in _tourneeKeysForUser(userId)) {
      final encoded = _box.get(key);
      if (encoded == null) continue;
      // Édition périmée ou entrée illisible : jamais réaffichée, autant rendre
      // la place tout de suite.
      if (!encoded.contains(dayMarker)) {
        stale.add(key);
        continue;
      }
      if (!key.startsWith(variantPrefix)) continue;
      try {
        final decoded = jsonDecode(encoded);
        final header = decoded is Map<String, dynamic> ? decoded['header'] : null;
        final data = decoded is Map<String, dynamic> ? decoded['data'] : null;
        if (header is! Map<String, dynamic> || data == null) {
          stale.add(key);
          continue;
        }
        result[key.substring(variantPrefix.length)] =
            CachedTourneeSection(header: header, data: data);
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            'FeedCacheService.readTourneeSectionsForToday corrupted: $e',
          );
        }
        stale.add(key);
      }
    }
    if (stale.isNotEmpty) unawaited(_box.deleteAll(stale));
    return result;
  }

  /// Propage un statut de lecture dans les sections Tournée persistées.
  ///
  /// Pré-filtre sur la **chaîne encodée** (`contains`) avant tout `jsonDecode` :
  /// même stratégie que l'invalidation content-scoped du backend
  /// (`app/services/feed_cache.py`) — les ids apparaissent verbatim dans le
  /// payload, donc une entrée qui ne porte pas l'article n'est jamais décodée.
  /// Renvoie le nombre d'entrées effectivement patchées.
  Future<int> patchTourneeContentStatus(
    String userId,
    String contentId,
    ContentStatus status,
  ) async {
    var patchedCount = 0;
    for (final key in _tourneeKeysForUser(userId)) {
      final encoded = _box.get(key);
      if (encoded == null || !encoded.contains(contentId)) continue;
      try {
        final decoded = jsonDecode(encoded);
        if (decoded is! Map<String, dynamic>) {
          await _box.delete(key);
          continue;
        }
        final data = decoded['data'];
        if (data == null) continue;
        if (!_patchStatusInData(data, contentId, status.name)) continue;
        await _box.put(key, jsonEncode(decoded));
        patchedCount++;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('FeedCacheService.patchTourneeContentStatus failed: $e');
        }
        await _box.delete(key);
      }
    }
    return patchedCount;
  }

  /// Remove cache entries for [userId] — entrées feed **et** sections Tournée.
  /// Use on logout or user switch.
  Future<void> clearForUser(String userId, {FeedCacheVariant? variant}) async {
    if (variant != null) {
      final sectionPrefix = '${_tourneeUserPrefix(userId)}${variant.name}:';
      await _box.deleteAll([
        _key(userId, variant),
        if (variant == FeedCacheVariant.normal) _legacyKey(userId),
        for (final key in _tourneeKeysForUser(userId))
          if (key.startsWith(sectionPrefix)) key,
      ]);
      return;
    }
    await _box.deleteAll([
      _key(userId, FeedCacheVariant.normal),
      _key(userId, FeedCacheVariant.serein),
      _legacyKey(userId),
      ..._tourneeKeysForUser(userId),
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

/// Entrée « section de la Tournée » persistée (SWR in-day).
///
/// Pas de `savedAt` ici, contrairement à [CachedFeedRaw] : la fraîcheur d'une
/// section n'est pas un TTL glissant mais le `day_key` de l'édition, déjà filtré
/// par [FeedCacheService.readTourneeSectionsForToday].
class CachedTourneeSection {
  /// En-tête d'affichage de la section (label, accent, logo…), sérialisé par
  /// le provider depuis la section **réellement rendue**. Permet de reconstruire
  /// la section sans `userSourcesProvider` / `veilleActiveConfigProvider`, qui
  /// ne sont pas résolus au boot (lecture `_peekValue`, sans initialisation).
  final Map<String, dynamic> header;

  /// Payload brut de `GET /api/feed`, prêt pour `FeedRepository.parseFeedData`.
  final dynamic data;

  const CachedTourneeSection({required this.header, required this.data});
}
