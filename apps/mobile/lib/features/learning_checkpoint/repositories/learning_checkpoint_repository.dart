import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/providers.dart';
import '../models/learning_proposal_model.dart';

/// Wrappe les endpoints Epic 13 : `GET /learning-proposals` + `POST /apply-proposals`.
///
/// Règles :
/// - `fetchProposals` : liste vide sur 404/500/timeout (silent fail, carte simplement non affichée).
/// - `applyProposals` : exception propagée, gérée en aval par le notifier.
class LearningCheckpointRepository {
  final ApiClient _api;

  LearningCheckpointRepository(this._api);

  Future<List<LearningProposal>> fetchProposals() async {
    try {
      final data = await _api.get(
        'learning-proposals',
        options: Options(
          sendTimeout: const Duration(seconds: 2),
          receiveTimeout: const Duration(seconds: 2),
        ),
      );
      if (data is! List) return const [];
      return data
          .whereType<Map<String, dynamic>>()
          .map(LearningProposal.fromJson)
          .toList();
    } on DioException catch (e) {
      _logNonFatal(e);
      return const [];
    } catch (e, s) {
      debugPrint('LearningCheckpointRepository.fetchProposals error: $e\n$s');
      return const [];
    }
  }

  Future<ApplyProposalsResponse> applyProposals(
    List<ApplyAction> actions,
  ) async {
    final data = await _api.post(
      'apply-proposals',
      body: {'actions': actions.map((a) => a.toJson()).toList()},
    );
    if (data is Map<String, dynamic>) {
      return ApplyProposalsResponse.fromJson(data);
    }
    return const ApplyProposalsResponse(updatedPreferences: []);
  }

  void _logNonFatal(DioException e) {
    debugPrint(
      'LearningCheckpointRepository non-fatal: ${e.type} '
      '(${e.response?.statusCode ?? '—'}) ${e.message ?? ''}',
    );
  }
}

final learningCheckpointRepositoryProvider =
    Provider<LearningCheckpointRepository>((ref) {
  return LearningCheckpointRepository(ref.read(apiClientProvider));
});
