import 'dart:async';

import 'package:dio/dio.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

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
      final response = await _dio.post<dynamic>(
        'veille/config',
        data: body.toJson(),
      );
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

  // ─── Suggestion d'angles LLM (Step 2) ──────────────────────────────────

  /// `POST /api/veille/suggest/angles` — suggère des angles éditoriaux (titre +
  /// grappe de mots-clés) pour un thème/brief via LLM (~10-15 s côté backend,
  /// cache 24 h). Toute erreur/timeout → **liste vide** : l'UI retombe alors
  /// sur les preset topics statiques, donc aucune régression si le LLM est KO.
  Future<List<VeilleAngleSuggestionDto>> suggestAngles({
    required String themeId,
    required String themeLabel,
    String brief = '',
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        'veille/suggest/angles',
        data: {'theme_id': themeId, 'theme_label': themeLabel, 'brief': brief},
      );
      return VeilleSuggestAnglesResponse.fromJson(
        response.data as Map<String, dynamic>,
      ).angles;
    } catch (_) {
      // Erreur réseau/timeout (DioException) ou réponse inattendue/parsing :
      // on dégrade en silence vers les preset topics statiques.
      return const [];
    }
  }

  // ─── Résolution sujet local Veille (Step 1) ─────────────────────────────

  /// `POST /api/veille/resolve/topic` — enrichit un sujet libre pour la veille
  /// sans créer d'intérêt global. Erreur → exception visible par l'UI Step 1.
  Future<VeilleResolvedTopicDto> resolveTopic({
    required String topic,
    String? themeId,
    String? themeLabel,
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        'veille/resolve/topic',
        data: {
          'topic': topic,
          if (themeId != null) 'theme_id': themeId,
          if (themeLabel != null) 'theme_label': themeLabel,
        },
      );
      return VeilleResolvedTopicDto.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  // ─── Suggestion sources LLM (Step 3) ───────────────────────────────────

  /// `POST /api/veille/suggest/sources` — candidats niche non ingérés.
  /// Les erreurs transport/API remontent en `VeilleApiException` pour que l'UI
  /// affiche un état retry. Une réponse 200 vide reste un vide légitime ;
  /// une réponse 200 malformée se dégrade en `[]`.
  Future<List<VeilleSourceSuggestionDto>> suggestSources({
    required String themeId,
    required String themeLabel,
    String brief = '',
    List<String> angles = const [],
    List<String> keywords = const [],
  }) async {
    try {
      final response = await _dio.post<dynamic>(
        'veille/suggest/sources',
        data: {
          'theme_id': themeId,
          'theme_label': themeLabel,
          'brief': brief,
          'angles': angles,
          'keywords': keywords,
        },
      );
      return VeilleSuggestSourcesResponse.fromJson(
        response.data as Map<String, dynamic>,
      ).sources;
    } on DioException catch (e, st) {
      unawaited(
        Sentry.captureException(
          e,
          stackTrace: st,
          withScope: (scope) {
            scope.setTag('endpoint', 'veille_suggest_sources');
            final code = e.response?.statusCode;
            scope.setContexts('veille_suggest_sources', {
              'path': e.requestOptions.path,
              if (code != null) 'statusCode': code,
            });
          },
        ),
      );
      throw _wrap(e);
    } catch (e) {
      unawaited(
        Sentry.captureMessage(
          'veille_suggest_sources_malformed_response',
          level: SentryLevel.warning,
          withScope: (scope) {
            scope.setTag('endpoint', 'veille_suggest_sources');
            scope.setContexts('veille_suggest_sources', {
              'error': e.toString(),
            });
          },
        ),
      );
      return const [];
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
