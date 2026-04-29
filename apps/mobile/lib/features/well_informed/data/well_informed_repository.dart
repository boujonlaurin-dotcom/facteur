import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_provider.dart';

/// Repository pour la soumission de la note "bien informé" (Story 14.3).
///
/// `POST /well-informed/ratings` (voir `packages/api/app/routers/well_informed.py`).
/// Fail silencieux : l'event analytics est firé séparément, donc une erreur
/// réseau ici ne perd pas la donnée d'usage — seule la ligne canonique en DB
/// manque. Le cooldown côté client avance quand même pour éviter de spammer.
class WellInformedRepository {
  WellInformedRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<void> submitRating({
    required int score,
    String context = 'digest_inline',
  }) async {
    assert(score >= 1 && score <= 10, 'Score hors bornes 1..10');
    try {
      await _apiClient.dio.post<void>(
        'well-informed/ratings',
        data: {'score': score, 'context': context},
      );
    } catch (e) {
      debugPrint('WellInformedRepository: POST failed — $e');
    }
  }
}

final wellInformedRepositoryProvider = Provider<WellInformedRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return WellInformedRepository(apiClient);
});
