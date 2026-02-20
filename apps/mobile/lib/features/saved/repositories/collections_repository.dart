import 'package:flutter/foundation.dart';

import '../../../core/api/api_client.dart';
import '../../feed/models/content_model.dart';
import '../models/collection_model.dart';

class CollectionsRepository {
  final ApiClient _apiClient;

  CollectionsRepository(this._apiClient);

  Future<List<Collection>> listCollections() async {
    try {
      final response = await _apiClient.dio.get<List<dynamic>>(
        'collections/',
      );

      if (response.statusCode == 200 && response.data != null) {
        return response.data!
            .whereType<Map<String, dynamic>>()
            .map((e) => Collection.fromJson(e))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('CollectionsRepository: [ERROR] listCollections: $e');
      // Return empty list on error (e.g. 404 when backend not deployed yet)
      return [];
    }
  }

  Future<Collection> createCollection(String name) async {
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        'collections/',
        data: {'name': name},
      );

      if (response.statusCode == 201 && response.data != null) {
        return Collection.fromJson(response.data!);
      }
      throw Exception('Failed to create collection: ${response.statusCode}');
    } catch (e) {
      debugPrint('CollectionsRepository: [ERROR] createCollection: $e');
      rethrow;
    }
  }

  Future<Collection> updateCollection(String collectionId, String name) async {
    try {
      final response = await _apiClient.dio.patch<Map<String, dynamic>>(
        'collections/$collectionId',
        data: {'name': name},
      );

      if (response.statusCode == 200 && response.data != null) {
        return Collection.fromJson(response.data!);
      }
      throw Exception('Failed to update collection: ${response.statusCode}');
    } catch (e) {
      debugPrint('CollectionsRepository: [ERROR] updateCollection: $e');
      rethrow;
    }
  }

  Future<void> deleteCollection(String collectionId) async {
    try {
      await _apiClient.dio.delete<void>('collections/$collectionId');
    } catch (e) {
      debugPrint('CollectionsRepository: [ERROR] deleteCollection: $e');
      rethrow;
    }
  }

  Future<List<Content>> getCollectionItems({
    required String collectionId,
    int limit = 20,
    int offset = 0,
    String sort = 'recent',
  }) async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        'collections/$collectionId/items',
        queryParameters: {
          'limit': limit,
          'offset': offset,
          'sort': sort,
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final items = response.data!['items'] as List<dynamic>?;
        if (items != null) {
          return items
              .whereType<Map<String, dynamic>>()
              .map((e) => Content.fromJson(e))
              .toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint('CollectionsRepository: [ERROR] getCollectionItems: $e');
      rethrow;
    }
  }

  Future<void> addToCollection(String collectionId, String contentId) async {
    try {
      await _apiClient.dio.post<void>(
        'collections/$collectionId/items',
        data: {'content_id': contentId},
      );
    } catch (e) {
      debugPrint('CollectionsRepository: [ERROR] addToCollection: $e');
      rethrow;
    }
  }

  Future<void> removeFromCollection(
      String collectionId, String contentId) async {
    try {
      await _apiClient.dio
          .delete<void>('collections/$collectionId/items/$contentId');
    } catch (e) {
      debugPrint('CollectionsRepository: [ERROR] removeFromCollection: $e');
      rethrow;
    }
  }

  Future<void> saveWithCollections(
      String contentId, List<String> collectionIds) async {
    try {
      await _apiClient.dio.post<void>(
        'contents/$contentId/save',
        data: {'collection_ids': collectionIds},
      );
    } catch (e) {
      debugPrint('CollectionsRepository: [ERROR] saveWithCollections: $e');
      rethrow;
    }
  }

  Future<SavedSummary> getSavedSummary() async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        'collections/saved-summary',
      );

      if (response.statusCode == 200 && response.data != null) {
        return SavedSummary.fromJson(response.data!);
      }
      return SavedSummary();
    } catch (e) {
      debugPrint('CollectionsRepository: [ERROR] getSavedSummary: $e');
      return SavedSummary();
    }
  }
}
