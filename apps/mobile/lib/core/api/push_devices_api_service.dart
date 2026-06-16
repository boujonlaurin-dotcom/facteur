import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

class PushDevicesApiService {
  PushDevicesApiService(this._apiClient);

  final ApiClient _apiClient;

  Future<bool> upsert({
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
      return true;
    } on DioException catch (e) {
      debugPrint('PushDevicesApi: PUT failed: ${e.message}');
      return false;
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
