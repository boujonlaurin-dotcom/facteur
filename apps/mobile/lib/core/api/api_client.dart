import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/constants.dart';
import '../auth/session_refresher.dart';
import 'retry_interceptor.dart';

/// Client API basé sur Dio avec authentification automatique
class ApiClient {
  /// Detail exact renvoyé par le backend quand l'email n'est pas confirmé.
  /// DOIT rester synchronisé avec `packages/api/app/dependencies.py`
  /// (`HTTPException(status_code=403, detail="Email not confirmed")`).
  static const String _emailNotConfirmedDetail = 'Email not confirmed';

  late final Dio _dio;
  final SupabaseClient _supabase;
  final void Function(int code)? onAuthError;

  /// Callback invoqué quand une requête aboutit après un état d'erreur auth
  /// (ex. 403 email_not_confirmed récupéré via refresh+retry). Permet au
  /// caller de clear `forceUnconfirmed` même si le JWT local est encore stale
  /// (le backend a fait fallback DB et accepté la requête).
  final void Function()? onAuthRecovered;

  ApiClient(
    this._supabase, {
    String? baseUrl,
    this.onAuthError,
    this.onAuthRecovered,
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
            // Single-flight refresh via SessionRefresher : si plusieurs
            // requêtes parallèles reçoivent 401 (typique au resume après
            // background), un seul refresh est envoyé au SDK Supabase. Évite
            // la race "double-refresh" sur les refresh tokens single-use
            // (cf. docs/bugs/bug-android-disconnect-race.md).
            Session? refreshedSession;
            try {
              refreshedSession = await SessionRefresher.instance
                  .refresh(timeout: const Duration(seconds: 5));
            } catch (_) {
              // Refresh failed — recheck currentSession avant de logout :
              // un autre acteur (SDK auto-refresh) a peut-être obtenu une
              // session valide entre-temps.
              refreshedSession = _supabase.auth.currentSession;
            }

            if (refreshedSession != null) {
              try {
                final opts = error.requestOptions;
                opts.headers['Authorization'] =
                    'Bearer ${refreshedSession.accessToken}';
                final response = await _dio.fetch<dynamic>(opts);
                onAuthRecovered?.call();
                return handler.resolve(response);
              } catch (retryErr) {
                // Le retry a échoué pour une autre raison — laisser bubble.
                _logError(error);
                return handler.next(error);
              }
            }

            // Vraiment plus de session valide → signal logout
            if (onAuthError != null) {
              // ignore: avoid_print
              print(
                  '⛔️ ApiClient: 401 after refresh attempt — no valid session. Triggering onAuthError.');
              onAuthError!(401);
            }
          } else if (statusCode == 403) {
            // Un 403 `email_not_confirmed` peut provenir d'un JWT stale (le
            // user vient de confirmer mais son access token n'a pas encore été
            // roté). On tente un refresh + retry AVANT de verrouiller l'app sur
            // l'écran de confirmation. Cf. docs/bugs/bug-feed-403-auth-recovery.md
            //
            // RÈGLE : on ne déclenche `onAuthError(403)` (→ setForceUnconfirmed)
            // QUE si on a une preuve forte : un 2ème 403 obtenu après retry avec
            // un JWT frais. Toute autre issue (refresh timeout, session null,
            // erreur réseau au retry) laisse le 403 bubble up sans verrouiller
            // l'app — évite le lock irrémédiable sur réseau/DB lent.
            final detail = _extractErrorDetail(error.response?.data);
            final isEmailNotConfirmed = detail == _emailNotConfirmedDetail;

            if (isEmailNotConfirmed) {
              Session? refreshedSession;
              try {
                refreshedSession = await SessionRefresher.instance
                    .refresh(timeout: const Duration(seconds: 5));
              } catch (e) {
                // Refresh timeout ou AuthException — on ne verrouille PAS l'app
                // sur un échec transitoire. Le 403 original bubble au caller
                // (FeedNotifier le rendra comme une erreur récupérable).
                // ignore: avoid_print
                print(
                    '⚠️ ApiClient: 403 refresh failed (${e.runtimeType}), not triggering onAuthError — bubbling original 403.');
              }

              if (refreshedSession != null) {
                final opts = error.requestOptions;
                opts.headers['Authorization'] =
                    'Bearer ${refreshedSession.accessToken}';
                try {
                  final response = await _dio.fetch<dynamic>(opts);
                  // ignore: avoid_print
                  print(
                      '✅ ApiClient: 403 recovered via refresh+retry (stale JWT).');
                  onAuthRecovered?.call();
                  return handler.resolve(response);
                } on DioException catch (retryErr) {
                  // Toujours 403 après refresh → l'email est réellement non
                  // confirmé : seule voie qui déclenche `onAuthError(403)`.
                  if (retryErr.response?.statusCode == 403 &&
                      onAuthError != null) {
                    // ignore: avoid_print
                    print(
                        '⛔️ ApiClient: 403 persists after refresh. Triggering onAuthError(403).');
                    onAuthError!(403);
                  }
                  _logError(retryErr);
                  return handler.next(retryErr);
                }
              }
            }
            // Aucun fallthrough vers onAuthError(403) ici : les 403 transients
            // et non-email (rate limit, RLS) passent tels quels au caller.
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

  /// Extrait le champ `detail` d'une réponse d'erreur FastAPI (si dispo).
  String? _extractErrorDetail(dynamic data) {
    if (data is Map && data['detail'] is String) {
      return data['detail'] as String;
    }
    return null;
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

  /// Helper PUT
  Future<dynamic> put(
    String path, {
    dynamic body,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    final response = await _dio.put(
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
