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

  const FluxContinuSnapshot({
    required this.dual,
    required this.topThemes,
    required this.essentielArticles,
  });
}

class FluxContinuCacheService {
  static const String boxName = 'flux_continu_cache';
  static const String _snapshotKey = 'latest_snapshot';

  Future<Box<String>> _box() async {
    if (Hive.isBoxOpen(boxName)) return Hive.box<String>(boxName);
    return Hive.openBox<String>(boxName);
  }

  Future<FluxContinuSnapshot?> readToday({DateTime? now}) async {
    try {
      final box = await _box();
      final raw = box.get(_snapshotKey);
      if (raw == null || raw.isEmpty) return null;
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      final dayKey = json['day_key'] as String?;
      if (dayKey != TourneeProgressService.dayKey(now ?? DateTime.now())) {
        return null;
      }
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
      );
    } catch (e) {
      debugPrint('FluxContinuCache: read failed: $e');
      return null;
    }
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
}
