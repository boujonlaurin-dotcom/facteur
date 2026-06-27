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
  ///
  /// [serein] force le mode côté backend (`?serein=`) au lieu de dépendre de la
  /// persistance DB de la préférence : évite la race au toggle (refetch avant
  /// que la préférence soit écrite). Absent ⇒ le backend lit la préférence DB.
  ///
  /// [date] cible une **édition passée** (`?target_date=YYYY-MM-DD`) pour le
  /// sélecteur de date de l'Essentiel (EPIC « Lettre du jour »). Absent ⇒
  /// aujourd'hui (l'appel historique du flux reste valide). Même format que
  /// `DigestRepository.getDigest`/`fetchBothDigests`.
  Future<List<EssentielArticle>?> fetch({bool? serein, DateTime? date}) async {
    try {
      final response = await _apiClient.dio.get<dynamic>(
        'essentiel',
        queryParameters: {
          if (serein != null) 'serein': serein,
          if (date != null) 'target_date': date.toIso8601String().split('T')[0],
        },
      );
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
          .map(EssentielArticle.fromJson)
          .toList(growable: false);
    } on DioException catch (e) {
      // ignore: avoid_print
      print('EssentielRepository: fetch failed: ${e.message}');
      return null;
    }
  }
}

final essentielRepositoryProvider = Provider<EssentielRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return EssentielRepository(apiClient);
});
