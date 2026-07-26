import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../models/alert_item.dart';

/// Accès aux cloches « alerte source rare » (Epic 30, story 30.2).
class AlertsRepository {
  final ApiClient _apiClient;

  AlertsRepository(this._apiClient);

  Future<AlertsState> listAlerts() async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>('alerts');
    final data = response.data;
    if (data == null) return const AlertsState();
    return AlertsState.fromJson(data);
  }

  /// Pose ou retire la cloche. Renvoie le nouveau compteur pour l'en-tête.
  ///
  /// Traduit les deux refus métier en exceptions typées : l'appelant doit
  /// pouvoir distinguer « plafond atteint » (l'utilisateur doit en libérer
  /// une) de « source trop bavarde » (l'alerte n'est pas le bon geste), les
  /// deux menant à des copies différentes.
  Future<AlertsState> setAlert(String sourceId, bool enabled) async {
    try {
      final response = await _apiClient.dio.put<Map<String, dynamic>>(
        'sources/$sourceId/alert',
        data: {'enabled': enabled},
      );
      final data = response.data ?? const <String, dynamic>{};
      return AlertsState(
        activeCount: (data['active_count'] as num?)?.toInt() ?? 0,
        cap: (data['cap'] as num?)?.toInt() ?? 5,
      );
    } on DioException catch (e) {
      _maybeThrowTyped(e);
      rethrow;
    }
  }

  /// Format backend : `{ "detail": { "error": "...", "cap": 5 } }`.
  void _maybeThrowTyped(DioException e) {
    final status = e.response?.statusCode;
    if (status != 409 && status != 422) return;
    final raw = e.response?.data;
    if (raw is! Map || raw['detail'] is! Map) return;
    final detail = raw['detail'] as Map;
    switch (detail['error']) {
      case 'alert_cap_reached':
        throw AlertCapReachedException((detail['cap'] as num?)?.toInt() ?? 5);
      case 'source_not_rare':
        throw const SourceNotRareException();
    }
  }
}
