import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';
import '../models/topic_models.dart';

class TopicRepository {
  final ApiClient _apiClient;

  TopicRepository(this._apiClient);

  /// GET personalization/topics/ → list of [UserTopicProfile].
  /// Trailing slash required: backend uses redirect_slashes=False.
  Future<List<UserTopicProfile>> getTopics() async {
    try {
      final data = await _apiClient.get('personalization/topics/');

      if (data is List) {
        return data
            .whereType<Map<String, dynamic>>()
            .map((e) => UserTopicProfile.fromJson(e))
            .toList();
      }
      return [];
    } on DioException catch (e) {
      debugPrint(
          'TopicRepository: [ERROR] getTopics: ${e.response?.statusCode} ${e.message}');
      rethrow;
    }
  }

  /// POST personalization/topics/ → UserTopicProfile (LLM-enriched)
  /// Trailing slash required: backend uses redirect_slashes=False.
  Future<UserTopicProfile> followTopic(String name) async {
    try {
      final data = await _apiClient.post(
        'personalization/topics/',
        body: {'name': name},
      );
      return UserTopicProfile.fromJson(data as Map<String, dynamic>);
    } on DioException catch (e) {
      debugPrint(
          'TopicRepository: [ERROR] followTopic: ${e.response?.statusCode} ${e.response?.data}');
      rethrow;
    }
  }

  /// PUT personalization/topics/{id} → UserTopicProfile
  Future<UserTopicProfile> updateTopicPriority(
    String topicId,
    double priorityMultiplier,
  ) async {
    try {
      final data = await _apiClient.put(
        'personalization/topics/$topicId',
        body: {'priority_multiplier': priorityMultiplier},
      );
      return UserTopicProfile.fromJson(data as Map<String, dynamic>);
    } on DioException catch (e) {
      debugPrint(
          'TopicRepository: [ERROR] updateTopicPriority: ${e.response?.statusCode} ${e.response?.data}');
      rethrow;
    }
  }

  /// DELETE personalization/topics/{id} → 200
  Future<void> unfollowTopic(String topicId) async {
    try {
      await _apiClient.delete('personalization/topics/$topicId');
    } on DioException catch (e) {
      debugPrint(
          'TopicRepository: [ERROR] unfollowTopic: ${e.response?.statusCode} ${e.response?.data}');
      rethrow;
    }
  }

  /// GET personalization/topics/suggestions?theme={slug} → list of suggestion labels.
  Future<List<String>> getTopicSuggestions({String? theme}) async {
    try {
      final queryParams = <String, dynamic>{};
      if (theme != null) queryParams['theme'] = theme;

      final data = await _apiClient.get(
        'personalization/topics/suggestions',
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );

      if (data is List) {
        // API returns TopicSuggestion objects {slug, label, article_count}
        return data
            .whereType<Map<String, dynamic>>()
            .map((e) => (e['label'] as String?) ?? e['slug'].toString())
            .toList();
      }
      return [];
    } on DioException catch (e) {
      debugPrint(
          'TopicRepository: [ERROR] getTopicSuggestions: ${e.response?.statusCode} ${e.message}');
      // Graceful degradation: empty suggestions on error
      return [];
    }
  }
}
