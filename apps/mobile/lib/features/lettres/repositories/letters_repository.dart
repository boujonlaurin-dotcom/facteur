import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../models/letter.dart';

class LettersApiException implements Exception {
  final int? statusCode;
  final String message;
  const LettersApiException(this.message, {this.statusCode});
  @override
  String toString() =>
      'LettersApiException(status: $statusCode, message: $message)';
}

class LettersRepository {
  final ApiClient _apiClient;

  LettersRepository(this._apiClient);

  Dio get _dio => _apiClient.dio;

  Future<List<Letter>> getLetters() async {
    try {
      final response = await _dio.get<dynamic>('letters');
      final raw = response.data as List<dynamic>;
      return raw
          .whereType<Map<String, dynamic>>()
          .map(Letter.fromJson)
          .toList();
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  Future<Letter> refreshStatus(String letterId) async {
    try {
      final response =
          await _dio.post<dynamic>('letters/$letterId/refresh-status');
      return Letter.fromJson(response.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw _wrap(e);
    }
  }

  LettersApiException _wrap(DioException e) {
    final code = e.response?.statusCode;
    final detail = e.response?.data is Map
        ? (e.response?.data as Map)['detail']?.toString()
        : null;
    return LettersApiException(
      detail ?? e.message ?? 'erreur réseau',
      statusCode: code,
    );
  }
}
