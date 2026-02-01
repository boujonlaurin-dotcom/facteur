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

  /// Get or create today's digest for the current user
  Future<DigestResponse> getDigest({DateTime? targetDate}) async {
    try {
      final queryParams = <String, dynamic>{};
      if (targetDate != null) {
        queryParams['target_date'] = targetDate.toIso8601String().split('T')[0];
      }

      final response = await _apiClient.dio.get<dynamic>(
        'digest/', // Trailing slash to avoid 307 redirect which strips auth header
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        return DigestResponse.fromJson(data);
      }
      throw Exception('Failed to load digest: ${response.statusCode}');
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw DigestNotFoundException('No digest found for this date');
      } else if (e.response?.statusCode == 503) {
        throw DigestGenerationException(
            'Digest generation in progress or failed');
      }
      // ignore: avoid_print
      print('DigestRepository: [ERROR] getDigest: $e');
      rethrow;
    } catch (e) {
      // ignore: avoid_print
      print('DigestRepository: [ERROR] getDigest: $e');
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
      // ignore: avoid_print
      print('DigestRepository: [ERROR] getDigestById: $e');
      rethrow;
    } catch (e) {
      // ignore: avoid_print
      print('DigestRepository: [ERROR] getDigestById: $e');
      rethrow;
    }
  }

  /// Apply an action (read, save, not_interested, undo) to a digest item
  Future<void> applyAction({
    required String digestId,
    required String contentId,
    required String action, // 'read', 'save', 'not_interested', 'undo'
  }) async {
    try {
      await _apiClient.dio.post<dynamic>(
        'digest/$digestId/action',
        data: {
          'content_id': contentId,
          'action': action,
        },
      );
    } on DioException catch (e) {
      // ignore: avoid_print
      print('DigestRepository: [ERROR] applyAction DioException: ${e.message}');
      if (e.response?.data != null) {
        throw Exception('API Error: ${e.response?.data}');
      }
      rethrow;
    } catch (e) {
      // ignore: avoid_print
      print('DigestRepository: [ERROR] applyAction: $e');
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
      // ignore: avoid_print
      print(
          'DigestRepository: [ERROR] completeDigest DioException: ${e.message}');
      if (e.response?.data != null) {
        throw Exception('API Error: ${e.response?.data}');
      }
      rethrow;
    } catch (e) {
      // ignore: avoid_print
      print('DigestRepository: [ERROR] completeDigest: $e');
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
      // ignore: avoid_print
      print('DigestRepository: [ERROR] generateDigest: $e');
      rethrow;
    }
  }
}
