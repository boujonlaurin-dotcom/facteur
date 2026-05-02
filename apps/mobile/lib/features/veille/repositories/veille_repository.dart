import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../models/veille_config_dto.dart';
import '../models/veille_delivery.dart';
import '../models/veille_suggestion.dart';

/// Levée quand `GET /api/veille/config` renvoie 404 — pas de veille active
/// pour cet utilisateur. Le caller distingue cet état du reste pour
/// rediriger vers le flow de configuration au lieu de remonter une erreur.
class VeilleConfigNotFoundException implements Exception {
  const VeilleConfigNotFoundException();
  @override
  String toString() => 'VeilleConfigNotFoundException';
}

/// Erreur générique des endpoints `/api/veille/*` (4xx ou 5xx). Les retries
/// sur 5xx ≠503 sont déjà gérés par `RetryInterceptor` au niveau Dio
/// (`core/api/retry_interceptor.dart`). Au niveau caller, on ne re-tente
/// jamais — on remonte cette exception.
class VeilleApiException implements Exception {
  final int? statusCode;
  final String message;
  const VeilleApiException(this.message, {this.statusCode});
  @override
  String toString() =>
      'VeilleApiException(status: $statusCode, message: $message)';
}

class VeilleRepository {
  final ApiClient _apiClient;

  VeilleRepository(this._apiClient);

  Dio get _dio => _apiClient.dio;

  // ─── Config ────────────────────────────────────────────────────────────

  /// `GET /api/veille/config` → DTO si 200, `null` si 404 (pas de veille
  /// active). Toute autre erreur → `VeilleApiException`.
  Future<VeilleConfigDto?> getConfig() async {
    try {
      final response = await _dio.get<dynamic>('veille/config');
      final data = response.data as Map<String, dynamic>;
      return VeilleConfigDto.fromJson(data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null;
      }
      throw _wrap(e);
    }
  }

  Future<VeilleConfigDto> upsertConfig(VeilleConfigUpsertRequest body) async {
    try {
      final response =
          await _dio.post<dynamic>('veille/config', data: body.toJson());
      return VeilleConfigDto.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  Future<VeilleConfigDto> patchConfig(VeilleConfigPatchRequest body) async {
    try {
      final response =
          await _dio.patch<dynamic>('veille/config', data: body.toJson());
      return VeilleConfigDto.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw const VeilleConfigNotFoundException();
      }
      throw _wrap(e);
    }
  }

  Future<void> deleteConfig() async {
    try {
      await _dio.delete<dynamic>('veille/config');
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  // ─── Suggestions ───────────────────────────────────────────────────────

  Future<List<VeilleTopicSuggestion>> suggestTopics({
    required String themeId,
    required String themeLabel,
    List<String> selectedTopicIds = const [],
    List<String> excludeTopicIds = const [],
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        'veille/suggestions/topics',
        data: {
          'theme_id': themeId,
          'theme_label': themeLabel,
          'selected_topic_ids': selectedTopicIds,
          'exclude_topic_ids': excludeTopicIds,
        },
      );
      final raw = response.data as List<dynamic>;
      return raw
          .whereType<Map<String, dynamic>>()
          .map(VeilleTopicSuggestion.fromJson)
          .toList();
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  Future<VeilleSourceSuggestionsResponse> suggestSources({
    required String themeId,
    List<String> topicLabels = const [],
    List<String> excludeSourceIds = const [],
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        'veille/suggestions/sources',
        data: {
          'theme_id': themeId,
          'topic_labels': topicLabels,
          'exclude_source_ids': excludeSourceIds,
        },
      );
      return VeilleSourceSuggestionsResponse.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  // ─── Deliveries ────────────────────────────────────────────────────────

  Future<List<VeilleDeliveryListItem>> listDeliveries({int limit = 20}) async {
    try {
      final response = await _dio.get<dynamic>(
        'veille/deliveries',
        queryParameters: {'limit': limit},
      );
      final raw = response.data as List<dynamic>;
      return raw
          .whereType<Map<String, dynamic>>()
          .map(VeilleDeliveryListItem.fromJson)
          .toList();
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  Future<VeilleDeliveryResponse> getDelivery(String id) async {
    try {
      final response = await _dio.get<dynamic>('veille/deliveries/$id');
      return VeilleDeliveryResponse.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  VeilleApiException _wrap(DioException e) {
    final code = e.response?.statusCode;
    final detail = e.response?.data is Map
        ? (e.response?.data as Map)['detail']?.toString()
        : null;
    return VeilleApiException(
      detail ?? e.message ?? 'erreur réseau',
      statusCode: code,
    );
  }
}
