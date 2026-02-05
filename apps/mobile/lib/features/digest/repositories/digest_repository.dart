import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';
import '../models/digest_models.dart';

/// Exception thrown when digest is not found (404)
class DigestNotFoundException implements Exception {
  final String message;
  DigestNotFoundException([this.message = 'Digest not found']);
  @override
  String toString() => message;
}

/// Exception thrown when digest generation failed (503)
class DigestGenerationException implements Exception {
  final String message;
  DigestGenerationException([this.message = 'Digest generation failed']);
  @override
  String toString() => message;
}

/// Repository for digest-related API operations
class DigestRepository {
  final ApiClient _apiClient;

  DigestRepository(this._apiClient);

  /// Get today's digest for user
  Future<DigestResponse> getDigest({DateTime? date}) async {
    try {
      final queryParams = <String, dynamic>{};
      if (date != null) {
        queryParams['target_date'] = date.toIso8601String().split('T')[0];
      }

      // ignore: avoid_print
      print(
          'DigestRepository: GET digest ${queryParams.isNotEmpty ? queryParams : ""}');

      final response = await _apiClient.dio.get<dynamic>(
        'digest', // Removed trailing slash to match FastAPI exactly
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        // ignore: avoid_print
        print('DigestRepository: Received data keys: ${data.keys}');

        try {
          return DigestResponse.fromJson(data);
        } catch (e, stack) {
          // ignore: avoid_print
          print('DigestRepository: JSON PARSING ERROR: $e\n$stack');
          // ignore: avoid_print
          print('DigestRepository: Problematic JSON: $data');
          rethrow;
        }
      }
      throw Exception('Failed to load digest: ${response.statusCode}');
    } on DioException catch (e) {
      // ignore: avoid_print
      print('DigestRepository: DioException: ${e.message}');
      if (e.response?.statusCode == 404) {
        throw DigestNotFoundException();
      }
      if (e.response?.statusCode == 503) {
        throw DigestGenerationException();
      }
      rethrow;
    } catch (e) {
      // ignore: avoid_print
      print('DigestRepository: Unexpected error: $e');
      rethrow;
    }
  }

  /// Get a digest by its ID
  Future<DigestResponse> getDigestById(String digestId) async {
    try {
      final response = await _apiClient.dio.get<dynamic>(
        'digest/$digestId',
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        return DigestResponse.fromJson(data);
      }
      throw Exception('Failed to load digest: ${response.statusCode}');
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw DigestNotFoundException('Digest not found: $digestId');
      }
      rethrow;
    } catch (e) {
      rethrow;
    }
  }

  /// Apply an action (read, save, not_interested, undo, unsave) to a digest item
  Future<void> applyAction({
    required String digestId,
    required String contentId,
    required String
        action, // 'read', 'save', 'not_interested', 'undo', 'unsave'
  }) async {
    try {
      // Handle unsave as save with is_saved=false for API compatibility
      final apiAction = action == 'unsave' ? 'save' : action;
      final isSaved = action == 'unsave' ? false : null;

      await _apiClient.dio.post<dynamic>(
        'digest/$digestId/action',
        data: {
          'content_id': contentId,
          'action': apiAction,
          if (isSaved != null) 'is_saved': isSaved,
        },
      );
    } on DioException catch (e) {
      if (e.response?.data != null) {
        throw Exception('API Error: ${e.response?.data}');
      }
      rethrow;
    } catch (e) {
      rethrow;
    }
  }

  /// Complete a digest (mark as finished)
  Future<void> completeDigest(String digestId) async {
    try {
      await _apiClient.dio.post<dynamic>(
        'digest/$digestId/complete',
      );
    } on DioException catch (e) {
      if (e.response?.data != null) {
        throw Exception('API Error: ${e.response?.data}');
      }
      rethrow;
    } catch (e) {
      rethrow;
    }
  }

  /// Generate a new digest on-demand
  Future<DigestResponse> generateDigest() async {
    try {
      final response = await _apiClient.dio.post<dynamic>(
        'digest/generate',
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        return DigestResponse.fromJson(data);
      }
      throw Exception('Failed to generate digest: ${response.statusCode}');
    } catch (e) {
      rethrow;
    }
  }

  /// Force regenerate digest (deletes existing and creates new)
  Future<DigestResponse> forceRegenerateDigest() async {
    try {
      final response = await _apiClient.dio.post<dynamic>(
        'digest/generate',
        queryParameters: {'force': 'true'},
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        return DigestResponse.fromJson(data);
      }
      throw Exception('Failed to regenerate digest: ${response.statusCode}');
    } catch (e) {
      rethrow;
    }
  }
}
