import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

class PushDevicesApiService {
  PushDevicesApiService(this._apiClient);

  final ApiClient _apiClient;

  /// Enregistre l'appareil. Retourne `(ok, statusCode)` :
  /// - `ok` = succès 2xx ;
  /// - `statusCode` = code HTTP de la réponse d'erreur (ex. 503 si le push
  ///   serveur n'est pas configuré côté backend), ou `null` pour une erreur
  ///   réseau/timeout sans réponse. Surfacé pour le diagnostic de registration
  ///   (cf. bug-notif-matin-avatar-double-sans-bullets, Part 2 : root cause
  ///   « 0 device »).
  Future<({bool ok, int? statusCode})> upsert({
    required String deviceId,
    required String token,
    required String platform,
    required String timezone,
    String? appVersion,
  }) async {
    try {
      await _apiClient.dio.put<void>(
        'devices',
        data: {
          'device_id': deviceId,
          'fcm_token': token,
          'platform': platform,
          'timezone': timezone,
          if (appVersion != null) 'app_version': appVersion,
        },
      );
      return (ok: true, statusCode: null);
    } on DioException catch (e) {
      debugPrint(
        'PushDevicesApi: PUT failed: ${e.message} '
        '(status ${e.response?.statusCode})',
      );
      return (ok: false, statusCode: e.response?.statusCode);
    }
  }

  Future<void> revoke(String deviceId) async {
    try {
      await _apiClient.dio.delete<void>('devices/$deviceId');
    } on DioException catch (e) {
      debugPrint('PushDevicesApi: DELETE failed: ${e.message}');
    }
  }
}
