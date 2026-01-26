import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/providers.dart';
import '../../../core/api/api_client.dart';

final personalizationRepositoryProvider =
    Provider((ref) => PersonalizationRepository(ref.read(apiClientProvider)));

class PersonalizationRepository {
  final ApiClient _apiClient;

  PersonalizationRepository(this._apiClient);

  Future<void> muteSource(String sourceId) async {
    try {
      await _apiClient.post(
        'users/personalization/mute-source',
        body: {'source_id': sourceId},
      );
    } on DioException catch (e) {
      // Log détaillé pour diagnostic
      print('❌ PersonalizationRepository.muteSource failed:');
      print('   Status: ${e.response?.statusCode}');
      print('   Path: ${e.requestOptions.path}');
      print('   Body sent: {source_id: $sourceId}');
      print('   Response: ${e.response?.data}');
      print('   Error type: ${e.type}');
      rethrow;
    }
  }

  Future<void> muteTheme(String theme) async {
    try {
      await _apiClient.post(
        'users/personalization/mute-theme',
        body: {'theme': theme},
      );
    } on DioException catch (e) {
      print('❌ PersonalizationRepository.muteTheme failed:');
      print('   Status: ${e.response?.statusCode}');
      print('   Path: ${e.requestOptions.path}');
      print('   Body sent: {theme: $theme}');
      print('   Response: ${e.response?.data}');
      print('   Error type: ${e.type}');
      rethrow;
    }
  }

  Future<void> muteTopic(String topic) async {
    try {
      await _apiClient.post(
        'users/personalization/mute-topic',
        body: {'topic': topic},
      );
    } on DioException catch (e) {
      print('❌ PersonalizationRepository.muteTopic failed:');
      print('   Status: ${e.response?.statusCode}');
      print('   Path: ${e.requestOptions.path}');
      print('   Body sent: {topic: $topic}');
      print('   Response: ${e.response?.data}');
      print('   Error type: ${e.type}');
      rethrow;
    }
  }

  Future<void> unmuteSource(String sourceId) async {
    try {
      await _apiClient.delete('users/personalization/unmute-source/$sourceId');
    } on DioException catch (e) {
      print('❌ PersonalizationRepository.unmuteSource failed:');
      print('   Status: ${e.response?.statusCode}');
      print('   Path: ${e.requestOptions.path}');
      print('   SourceId: $sourceId');
      print('   Response: ${e.response?.data}');
      print('   Error type: ${e.type}');
      rethrow;
    }
  }
}
