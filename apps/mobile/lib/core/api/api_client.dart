import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/constants.dart';
import 'retry_interceptor.dart';

/// Client API basé sur Dio avec authentification automatique
class ApiClient {
  late final Dio _dio;
  final SupabaseClient _supabase;
  final void Function(int code)? onAuthError;

  ApiClient(
    this._supabase, {
    String? baseUrl,
    this.onAuthError,
  }) {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl ?? ApiConstants.baseUrl,
        // OPTIMIZATION: Increased from 10s to 30s to handle slow digest generation
        // Backend optimizations are in progress, this buys time for those to take effect
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: ApiConstants.timeout,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    _setupInterceptors();
  }

  /// Configure les interceptors Dio
  void _setupInterceptors() {
    // 1. Interceptor pour ajouter le JWT token automatiquement
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Try to get session, with a short wait if not immediately available
          var session = _supabase.auth.currentSession;

          // If no session, wait a bit and try again (race condition fix for Android release)
          if (session == null) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            session = _supabase.auth.currentSession;
          }

          if (session != null) {
            // ignore: avoid_print
            print(
                'ApiClient: Attaching token ${session.accessToken.substring(0, 10)}...');
            options.headers['Authorization'] = 'Bearer ${session.accessToken}';
          } else {
            // ignore: avoid_print
            print(
                'ApiClient: [WARNING] No session found, request will be anonymous.');
          }
          return handler.next(options);
        },
        onError: (error, handler) async {
          final statusCode = error.response?.statusCode;

          if (statusCode == 401) {
            // Attempt token refresh before signing out
            try {
              final refreshed = await _supabase.auth
                  .refreshSession()
                  .timeout(const Duration(seconds: 5));
              if (refreshed.session != null) {
                // Retry the original request with the new token
                final opts = error.requestOptions;
                opts.headers['Authorization'] =
                    'Bearer ${refreshed.session!.accessToken}';
                final response = await _dio.fetch<dynamic>(opts);
                return handler.resolve(response);
              }
            } catch (_) {
              // Refresh failed — fall through to onAuthError
            }
            // Refresh failed or returned no session — signal logout
            if (onAuthError != null) {
              // ignore: avoid_print
              print(
                  '⛔️ ApiClient: 401 after refresh attempt. Triggering onAuthError.');
              onAuthError!(401);
            }
          } else if (statusCode == 403) {
            if (onAuthError != null) {
              // ignore: avoid_print
              print(
                  '⛔️ ApiClient: Auth Error (403). Triggering onAuthError...');
              onAuthError!(403);
            }
          }

          // Logger les erreurs (sans les tokens)
          _logError(error);
          return handler.next(error);
        },
      ),
    );

    // 2. Interceptor de retry pour les erreurs réseau
    _dio.interceptors.add(
      RetryInterceptor(
        dio: _dio,
        maxRetries: 2,
        retryDelays: const [
          Duration(seconds: 1),
          Duration(seconds: 3),
        ],
      ),
    );
  }

  /// Logger les erreurs de manière sécurisée
  void _logError(DioException error) {
    // Ne jamais logger les tokens ou données sensibles
    final sanitizedError = {
      'statusCode': error.response?.statusCode,
      'type': error.type.toString(),
      'message': error.message,
      'path': error.requestOptions.path,
      'response': error.response?.data,
    };

    // En production, envoyer à Sentry
    // En dev, print simple
    // ignore: avoid_print
    print('API Error: $sanitizedError');
  }

  /// Accès au client Dio
  Dio get dio => _dio;

  /// Helper GET
  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    final response = await _dio.get(
      path,
      queryParameters: queryParameters,
      options: options,
    );
    return response.data;
  }

  /// Helper POST
  Future<dynamic> post(
    String path, {
    dynamic body,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    final response = await _dio.post(
      path,
      data: body,
      queryParameters: queryParameters,
      options: options,
    );
    return response.data;
  }

  /// Helper DELETE
  Future<dynamic> delete(
    String path, {
    dynamic body,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    final response = await _dio.delete<dynamic>(
      path,
      data: body,
      queryParameters: queryParameters,
      options: options,
    );
    return response.data;
  }

  /// Fermer le client
  void dispose() {
    _dio.close();
  }
}
