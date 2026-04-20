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
  Future<UserTopicProfile> followTopic(String name, {double? priorityMultiplier}) async {
    try {
      final body = <String, dynamic>{'name': name};
      if (priorityMultiplier != null) body['priority_multiplier'] = priorityMultiplier;
      final data = await _apiClient.post(
        'personalization/topics/',
        body: body,
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

  /// PUT personalization/topics/{id} → toggle `excluded_from_serein`.
  Future<UserTopicProfile> updateTopicSereinExclusion(
    String topicId,
    bool excluded,
  ) async {
    try {
      final data = await _apiClient.put(
        'personalization/topics/$topicId',
        body: {'excluded_from_serein': excluded},
      );
      return UserTopicProfile.fromJson(data as Map<String, dynamic>);
    } on DioException catch (e) {
      debugPrint(
          'TopicRepository: [ERROR] updateTopicSereinExclusion: ${e.response?.statusCode} ${e.response?.data}');
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

  /// POST personalization/topics/disambiguate → list of suggestions
  Future<List<DisambiguationSuggestion>> disambiguate(
    String name, {
    String? theme,
  }) async {
    try {
      final body = <String, dynamic>{'name': name};
      if (theme != null) body['theme'] = theme;

      final data = await _apiClient.post(
        'personalization/topics/disambiguate',
        body: body,
      );

      if (data is Map<String, dynamic>) {
        final suggestions = data['suggestions'] as List? ?? [];
        return suggestions
            .whereType<Map<String, dynamic>>()
            .map((e) => DisambiguationSuggestion.fromJson(e))
            .toList();
      }
      return [];
    } on DioException catch (e) {
      debugPrint(
          'TopicRepository: [ERROR] disambiguate: ${e.response?.statusCode} ${e.response?.data}');
      rethrow;
    }
  }

  /// POST personalization/topics/ with entity_type → UserTopicProfile
  Future<UserTopicProfile> followEntity(String name, String entityType) async {
    try {
      final data = await _apiClient.post(
        'personalization/topics/',
        body: {'name': name, 'entity_type': entityType},
      );
      return UserTopicProfile.fromJson(data as Map<String, dynamic>);
    } on DioException catch (e) {
      debugPrint(
          'TopicRepository: [ERROR] followEntity: ${e.response?.statusCode} ${e.response?.data}');
      rethrow;
    }
  }

  /// GET personalization/popular-entities → list of [PopularEntity].
  Future<List<PopularEntity>> getPopularEntities({String? theme, int limit = 10}) async {
    try {
      final queryParams = <String, dynamic>{'limit': limit};
      if (theme != null) queryParams['theme'] = theme;

      final data = await _apiClient.get(
        'personalization/popular-entities',
        queryParameters: queryParams,
      );

      if (data is List) {
        return data
            .whereType<Map<String, dynamic>>()
            .map((e) => PopularEntity.fromJson(e))
            .toList();
      }
      return [];
    } on DioException catch (e) {
      debugPrint(
          'TopicRepository: [ERROR] getPopularEntities: ${e.response?.statusCode} ${e.message}');
      return [];
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
