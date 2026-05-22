import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../models/veille_config_dto.dart';
import '../models/veille_source_example.dart';

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

  Future<void> deleteConfig() async {
    try {
      await _dio.delete<dynamic>('veille/config');
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  // ─── Suggesters LLM (Story 23.3) ───────────────────────────────────────

  /// `POST /api/veille/suggest/angles` — 5-8 angles + mots-clés explicites.
  /// Appel synchrone Mistral (~10-15s), affiche HaloLoader pendant l'appel.
  Future<VeilleSuggestAnglesResponse> suggestAngles(
    VeilleSuggestAnglesRequest body,
  ) async {
    try {
      final response = await _dio.post<dynamic>(
        'veille/suggest/angles',
        data: body.toJson(),
      );
      return VeilleSuggestAnglesResponse.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  /// `POST /api/veille/suggest/sources` — 5-10 sources rankées (≥3 même niche).
  /// Renvoie sources vides si LLM KO → mobile bascule sur le mode advanced URL.
  Future<VeilleSuggestSourcesResponse> suggestSources(
    VeilleSuggestSourcesRequest body,
  ) async {
    try {
      final response = await _dio.post<dynamic>(
        'veille/suggest/sources',
        data: body.toJson(),
      );
      return VeilleSuggestSourcesResponse.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  // ─── Sources curées (preview Step 3) ───────────────────────────────────

  /// `GET /api/veille/sources/{id}/examples` — preview ≤2 articles récents
  /// (Step 3 du flow). Le backend cache déjà 24 h ; ici pas de cache local.
  Future<List<VeilleSourceExample>> getSourceExamples(String sourceId) async {
    try {
      final response = await _dio.get<dynamic>(
        'veille/sources/$sourceId/examples',
      );
      final raw = response.data as List<dynamic>;
      return raw
          .whereType<Map<String, dynamic>>()
          .map(VeilleSourceExample.fromJson)
          .toList();
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
