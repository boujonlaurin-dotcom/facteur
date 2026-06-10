import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../digest/models/dual_digest_response.dart';
import '../models/flux_continu_models.dart';
import '../repositories/flux_continu_repository.dart';
import 'tournee_progress_service.dart';

class FluxContinuSnapshot {
  final DualDigestResponse dual;
  final List<TopTheme> topThemes;
  final List<EssentielArticle> essentielArticles;

  /// `true` quand le snapshot a été écrit un **autre jour** que celui passé à
  /// [FluxContinuCacheService.readLatest] (cache d'hier, invalidé chaque nuit).
  /// Le provider ne peint alors **jamais** ce contenu comme réel : il sert
  /// uniquement à confirmer qu'un snapshot existe. `false` = snapshot du jour
  /// (SWR in-day, peut être affiché tel quel puis revalidé).
  final bool isStale;

  /// Horodatage d'écriture (`saved_at`), lu pour le profiling / debug. `null`
  /// si absent ou illisible.
  final DateTime? savedAt;

  const FluxContinuSnapshot({
    required this.dual,
    required this.topThemes,
    required this.essentielArticles,
    this.isStale = false,
    this.savedAt,
  });
}

class FluxContinuCacheService {
  static const String boxName = 'flux_continu_cache';
  static const String _snapshotKey = 'latest_snapshot';

  Future<Box<String>> _box() async {
    if (Hive.isBoxOpen(boxName)) return Hive.box<String>(boxName);
    return Hive.openBox<String>(boxName);
  }

  /// Lit le dernier snapshot persisté **sans** le jeter sur un day mismatch :
  /// pose [FluxContinuSnapshot.isStale] = `(day_key != aujourd'hui)`. Le matin,
  /// le cache d'hier reste lisible (isStale:true) pour dessiner un squelette
  /// fidèle, mais le contenu n'est jamais affiché tel quel (cf. provider).
  /// Renvoie `null` uniquement si rien n'est persisté ou si le payload est
  /// corrompu.
  Future<FluxContinuSnapshot?> readLatest({DateTime? now}) async {
    try {
      final box = await _box();
      final raw = box.get(_snapshotKey);
      if (raw == null || raw.isEmpty) return null;
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      final dayKey = json['day_key'] as String?;
      final isStale =
          dayKey != TourneeProgressService.dayKey(now ?? DateTime.now());
      final dualJson = json['dual'];
      if (dualJson is! Map<String, dynamic>) return null;
      final topThemeJson = (json['top_themes'] as List?) ?? const [];
      final essentielJson = (json['essentiel_articles'] as List?) ?? const [];
      return FluxContinuSnapshot(
        dual: DualDigestResponse.fromJson(dualJson),
        topThemes: topThemeJson
            .whereType<Map<String, dynamic>>()
            .map(TopTheme.fromJson)
            .toList(growable: false),
        essentielArticles: essentielJson
            .whereType<Map<String, dynamic>>()
            .map(EssentielArticle.fromJson)
            .toList(growable: false),
        isStale: isStale,
        savedAt: DateTime.tryParse(json['saved_at'] as String? ?? ''),
      );
    } catch (e) {
      debugPrint('FluxContinuCache: read failed: $e');
      return null;
    }
  }

  /// Snapshot **du jour** uniquement (SWR in-day) — wrapper sur [readLatest]
  /// qui renvoie `null` dès que le snapshot est périmé (cache d'hier). Conservé
  /// pour les appelants qui ne veulent jamais de contenu périmé.
  Future<FluxContinuSnapshot?> readToday({DateTime? now}) async {
    final snapshot = await readLatest(now: now);
    if (snapshot == null || snapshot.isStale) return null;
    return snapshot;
  }

  Future<void> write({
    required DualDigestResponse dual,
    required List<TopTheme> topThemes,
    required List<EssentielArticle> essentielArticles,
    DateTime? now,
  }) async {
    try {
      final box = await _box();
      final payload = <String, dynamic>{
        'day_key': TourneeProgressService.dayKey(now ?? DateTime.now()),
        'saved_at': DateTime.now().toIso8601String(),
        'dual': dual.toJson(),
        'top_themes': topThemes.map((t) => t.toJson()).toList(growable: false),
        'essentiel_articles': essentielArticles
            .map((a) => a.toJson())
            .toList(growable: false),
      };
      await box.put(_snapshotKey, jsonEncode(payload));
    } catch (e) {
      debugPrint('FluxContinuCache: write failed: $e');
    }
  }

  Future<bool> patchContentConsumed(String contentId) async {
    try {
      final box = await _box();
      final raw = box.get(_snapshotKey);
      if (raw == null || raw.isEmpty) return false;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return false;
      var patched = false;

      void visit(dynamic value) {
        if (value is List) {
          for (final item in value) {
            visit(item);
          }
          return;
        }
        if (value is! Map<String, dynamic>) return;

        final id = value['id'] ?? value['content_id'];
        if (id == contentId) {
          if (value.containsKey('status')) value['status'] = 'consumed';
          if (value.containsKey('is_read')) value['is_read'] = true;
          if (value.containsKey('consumed')) value['consumed'] = true;
          patched = true;
        }
        for (final child in value.values) {
          visit(child);
        }
      }

      visit(decoded);
      if (!patched) return false;
      await box.put(_snapshotKey, jsonEncode(decoded));
      return true;
    } catch (e) {
      debugPrint('FluxContinuCache: patch consumed failed: $e');
      return false;
    }
  }
}
