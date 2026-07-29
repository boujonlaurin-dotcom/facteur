import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../models/alert_item.dart';

/// Devis de bruit d'un sujet, lu à l'ouverture de sa fiche.
///
/// Pendant de `sourceProfileProvider` côté source : la cadence coûte une
/// agrégation par sujet, donc elle n'est calculée que sur la fiche ouverte, pas
/// pour chaque chip de la liste.
class TopicFrequency {
  final int articles30d;
  final double cadencePerWeek;
  final String cadencePhrase;
  final bool noisy;

  const TopicFrequency({
    this.articles30d = 0,
    this.cadencePerWeek = 0,
    this.cadencePhrase = '',
    this.noisy = false,
  });

  factory TopicFrequency.fromJson(Map<String, dynamic> json) {
    return TopicFrequency(
      articles30d: (json['articles_30d'] as num?)?.toInt() ?? 0,
      cadencePerWeek: (json['cadence_per_week'] as num?)?.toDouble() ?? 0,
      cadencePhrase: json['cadence_phrase'] as String? ?? '',
      noisy: json['noisy'] == true,
    );
  }
}

/// Accès aux cloches d'alerte, sources et sujets (Epic 30, stories 30.2/30.3).
class AlertsRepository {
  final ApiClient _apiClient;

  AlertsRepository(this._apiClient);

  Future<AlertsState> listAlerts() async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>('alerts');
    final data = response.data;
    if (data == null) return const AlertsState();
    return AlertsState.fromJson(data);
  }

  /// Pose ou retire la cloche sur une source. Renvoie le nouveau compteur.
  Future<AlertsState> setAlert(
    String sourceId,
    bool enabled, {
    bool filtered = false,
  }) {
    return _putAlert('sources/$sourceId/alert', enabled, filtered);
  }

  /// Pose ou retire la cloche sur un sujet suivi.
  Future<AlertsState> setTopicAlert(
    String topicId,
    bool enabled, {
    bool filtered = false,
  }) {
    return _putAlert('personalization/topics/$topicId/alert', enabled, filtered);
  }

  Future<TopicFrequency> topicFrequency(String topicId) async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      'personalization/topics/$topicId/frequency',
    );
    final data = response.data;
    if (data == null) return const TopicFrequency();
    return TopicFrequency.fromJson(data);
  }

  Future<AlertsState> _putAlert(
    String path,
    bool enabled,
    bool filtered,
  ) async {
    try {
      final response = await _apiClient.dio.put<Map<String, dynamic>>(
        path,
        data: {'enabled': enabled, 'filtered': filtered},
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
  ///
  /// Un seul refus métier subsiste depuis les alertes v2 : le plafond.
  /// « Source trop bavarde » a disparu — la cloche est désormais posable
  /// partout, et le bruit se règle par le mode filtré.
  void _maybeThrowTyped(DioException e) {
    if (e.response?.statusCode != 409) return;
    final raw = e.response?.data;
    if (raw is! Map || raw['detail'] is! Map) return;
    final detail = raw['detail'] as Map;
    if (detail['error'] == 'alert_cap_reached') {
      throw AlertCapReachedException((detail['cap'] as num?)?.toInt() ?? 5);
    }
  }
}
