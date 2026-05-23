import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/providers.dart';
import '../models/flux_continu_models.dart';

/// `GET /api/essentiel` — Story 9.1/9.2.
///
/// Renvoie jusqu'à 5 articles transversaux cross-topic pour alimenter la
/// carte hi-fi "L'Essentiel du jour" en haut du feed. L'endpoint backend est
/// strictement read-only (réutilise la chaîne de fallback de `/api/digest`),
/// et peut renvoyer 202 `{"status":"preparing"}` quand aucun digest n'est
/// encore prêt — le provider traite ce cas comme une liste vide et conserve
/// son fallback construit depuis le digest classique.
class EssentielRepository {
  final ApiClient _apiClient;

  EssentielRepository(this._apiClient);

  /// Renvoie la liste des articles de l'Essentiel, ou `null` si l'endpoint
  /// n'a rien servi (202 ou erreur réseau). Le provider décide alors s'il
  /// veut fallback ou afficher une section vide.
  Future<List<EssentielArticle>?> fetch() async {
    try {
      final response = await _apiClient.dio.get<dynamic>('essentiel');
      if (response.statusCode == 202) {
        return null;
      }
      if (response.statusCode != 200 || response.data is! Map) {
        return null;
      }
      final data = response.data as Map<String, dynamic>;
      final raw = (data['articles'] as List?) ?? const [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(_parseArticle)
          .toList(growable: false);
    } on DioException catch (e) {
      // ignore: avoid_print
      print('EssentielRepository: fetch failed: ${e.message}');
      return null;
    }
  }

  static EssentielArticle _parseArticle(Map<String, dynamic> json) {
    final source = (json['source'] as Map?)?.cast<String, dynamic>() ?? const {};
    final sourceName = (source['name'] as String?) ?? '';
    return EssentielArticle(
      contentId: (json['content_id'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      url: (json['url'] as String?) ?? '',
      thumbnailUrl: json['thumbnail_url'] as String?,
      publishedAt: DateTime.tryParse(json['published_at'] as String? ?? '') ??
          DateTime.now(),
      sourceName: sourceName,
      sourceLetter: (json['source_letter'] as String?) ?? _initial(sourceName),
      kind: _parseKind(json['kind'] as String?),
      theme: json['theme'] as String?,
      sectionLabel: (json['section_label'] as String?) ?? '',
      perspectiveCount: (json['perspective_count'] as num?)?.toInt() ?? 0,
      rank: (json['rank'] as num?)?.toInt() ?? 0,
      isRead: (json['is_read'] as bool?) ?? false,
      isSaved: (json['is_saved'] as bool?) ?? false,
      isLiked: (json['is_liked'] as bool?) ?? false,
      isDismissed: (json['is_dismissed'] as bool?) ?? false,
    );
  }

  static String _initial(String name) {
    for (final ch in name.trim().split('')) {
      if (ch.trim().isNotEmpty) return ch.toUpperCase();
    }
    return '?';
  }

  static SectionKind _parseKind(String? raw) {
    switch (raw) {
      case 'bonnes':
        return SectionKind.bonnes;
      case 'veille':
        return SectionKind.veille;
      case 'essentiel':
        return SectionKind.essentiel;
      case 'theme':
      default:
        return SectionKind.theme;
    }
  }
}

final essentielRepositoryProvider = Provider<EssentielRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return EssentielRepository(apiClient);
});
