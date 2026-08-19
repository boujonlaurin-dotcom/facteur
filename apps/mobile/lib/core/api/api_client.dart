import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/constants.dart';
import '../auth/session_refresher.dart';
import 'retry_interceptor.dart';
import 'user_error_interceptor.dart';

/// Notifier global pour les 410 Gone interceptés par [ApiClient].
///
/// Story 23.2 PR-4 — quand un endpoint retiré (par exemple les routes LLM
/// `/api/veille/suggestions/*` ou `/api/veille/deliveries/*` post-Story 23.1)
/// est appelé par un client mobile pas encore à jour, le backend répond
/// 410 Gone. L'UI top-level peut écouter ce notifier pour afficher un banner
/// "Mise à jour requise" sans coupler ApiClient à un BuildContext.
///
/// Implémenté comme singleton lazy parce que ApiClient est instancié dans un
/// provider Riverpod et n'a pas accès au Navigator/Overlay/ScaffoldMessenger.
class ApiGoneNotifier extends ChangeNotifier {
  ApiGoneNotifier._();
  static final ApiGoneNotifier instance = ApiGoneNotifier._();

  String? _lastGonePath;
  String? get lastGonePath => _lastGonePath;

  void onGoneReceived(String path) {
    _lastGonePath = path;
    notifyListeners();
  }

  void clear() {
    if (_lastGonePath == null) return;
    _lastGonePath = null;
    notifyListeners();
  }
}

/// Client API basé sur Dio avec authentification automatique
class ApiClient {
  /// Detail exact renvoyé par le backend quand l'email n'est pas confirmé.
  /// DOIT rester synchronisé avec `packages/api/app/dependencies.py`
  /// (`HTTPException(status_code=403, detail="Email not confirmed")`).
  static const String _emailNotConfirmedDetail = 'Email not confirmed';

  /// Marqueur posé sur les requêtes parties **sans** header `Authorization`.
  /// Un 401 sur une telle requête ne prouve rien sur la validité de la session
  /// et ne doit jamais déclencher `handleSessionExpired` (cf. C3 de
  /// `docs/bugs/bug-widget-fiabilite.md`).
  static const String _anonymousRequestFlag = 'facteur_anonymous_request';

  /// Token porté par la requête, mémorisé pour savoir *lequel* le backend a
  /// rejeté — c'est la seule information qui distingue « mon JWT est périmé »
  /// de « un autre acteur a déjà roté le token pendant que j'attendais ».
  static const String _sentAccessTokenKey = 'facteur_sent_access_token';

  /// Marque un rejeu piloté par [_recoverUnauthorized]. Sert à borner les
  /// requêtes : un rejeu ne redéclenche jamais la récupération.
  static const String _authRecoveryRequestFlag =
      'facteur_auth_recovery_request';

  /// Nombre maximum de rejeux d'une requête après un 401.
  static const int _maxAuthReplays = 2;

  /// Budget d'attente d'une session au moment d'émettre une requête.
  ///
  /// Les 100 ms d'origine étaient calibrées pour une race Riverpod ; elles ne
  /// couvrent pas un cold boot (restauration Hive + `recoverSession` Supabase),
  /// où l'app partait en anonyme, prenait un 401 et se déloguait. Même esprit
  /// que `resolveMorningRitualMaxWait` : on laisse le temps au démarrage à
  /// froid, sans jamais bloquer une requête qui a déjà sa session.
  static const Duration _defaultSessionWaitBudget = Duration(seconds: 2);
  static const Duration _sessionPollInterval = Duration(milliseconds: 100);

  late final Dio _dio;
  final SupabaseClient _supabase;
  final CurrentSessionFn? _currentSessionFnOverride;
  late final CurrentSessionFn _currentSession =
      _currentSessionFnOverride ?? () => _supabase.auth.currentSession;
  final Duration _sessionWaitBudget;
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
    String? appVersion,
    @visibleForTesting CurrentSessionFn? currentSessionFnOverride,
    @visibleForTesting Duration sessionWaitBudget = _defaultSessionWaitBudget,
    @visibleForTesting HttpClientAdapter? httpClientAdapter,
  })  : _currentSessionFnOverride = currentSessionFnOverride,
        _sessionWaitBudget = sessionWaitBudget {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (appVersion != null) 'X-App-Version': appVersion,
    };
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl ?? ApiConstants.baseUrl,
        // OPTIMIZATION: Increased from 10s to 30s to handle slow digest generation
        // Backend optimizations are in progress, this buys time for those to take effect
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: ApiConstants.timeout,
        headers: headers,
      ),
    );
    if (httpClientAdapter != null) {
      _dio.httpClientAdapter = httpClientAdapter;
    }

    _setupInterceptors();
  }

  /// Configure les interceptors Dio
  void _setupInterceptors() {
    // 1. Interceptor pour ajouter le JWT token automatiquement
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Les replays auth ont déjà reçu explicitement le token à tester.
          // Ne pas le remplacer pendant leur nouveau passage dans Dio.
          if (options.extra[_authRecoveryRequestFlag] == true) {
            return handler.next(options);
          }

          final session = await _awaitSession();

          if (session != null) {
            // ignore: avoid_print
            print(
                'ApiClient: Attaching token ${session.accessToken.substring(0, 10)}...');
            options.headers['Authorization'] = 'Bearer ${session.accessToken}';
            options.extra[_sentAccessTokenKey] = session.accessToken;
          } else {
            // Requête émise quand même : certains endpoints sont publics. Mais
            // on la marque pour que son éventuel 401 ne puisse pas être lu
            // comme une session expirée.
            options.extra[_anonymousRequestFlag] = true;
            // ignore: avoid_print
            print(
                'ApiClient: [WARNING] No session after ${_sessionWaitBudget.inMilliseconds}ms, request will be anonymous.');
          }
          return handler.next(options);
        },
        onError: (error, handler) async {
          final statusCode = error.response?.statusCode;

          if (statusCode == 401) {
            // `_dio.fetch` repasse par les interceptors. Les replays sont
            // pilotés explicitement par le premier 401 afin de borner les
            // requêtes ; leurs erreurs doivent simplement lui remonter.
            if (error.requestOptions.extra[_authRecoveryRequestFlag] == true) {
              return handler.next(error);
            }

            // La requête est partie sans header : le 401 est attendu et ne dit
            // rien de la session. La traiter comme une expiration déconnectait
            // l'utilisateur au cold boot (C3). On laisse le 401 remonter au
            // caller, sans refresh ni `onAuthError`.
            if (error.requestOptions.extra[_anonymousRequestFlag] == true) {
              // ignore: avoid_print
              print(
                  'ApiClient: 401 on an anonymous request (${error.requestOptions.path}) — no session to expire, not signing out.');
              _logError(error);
              return handler.next(error);
            }

            try {
              final response = await _recoverUnauthorized(error);
              onAuthRecovered?.call();
              return handler.resolve(response);
            } on DioException catch (finalError) {
              _logError(finalError);
              return handler.next(finalError);
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
          } else if (statusCode == 410) {
            // Story 23.2 PR-4 : un 410 Gone signale que l'endpoint a été retiré
            // (cas des endpoints LLM veille post-Story 23.1). Les vieux clients
            // mobile qui tomberaient ici doivent être invités à mettre à jour.
            // ignore: avoid_print
            print(
                '⚠️ ApiClient: 410 Gone on ${error.requestOptions.path} — endpoint retired. User should update.');
            ApiGoneNotifier.instance.onGoneReceived(error.requestOptions.path);
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

    // 3. Interceptor « souci côté device » : remonte à l'utilisateur les 5xx /
    // timeouts d'un appel opt-in (`extra['userFacing'] == true`), APRÈS les
    // retries. Silencieux sinon.
    _dio.interceptors.add(UserErrorInterceptor());
  }

  /// Attend une session Supabase jusqu'à [_sessionWaitBudget], en sortant dès
  /// qu'elle est disponible. Retourne `null` si le budget est épuisé.
  ///
  /// Coût nul sur le chemin nominal (session déjà là → retour immédiat) ; le
  /// budget ne s'applique qu'au cold boot, où la session est en cours de
  /// restauration depuis Hive.
  Future<Session?> _awaitSession() async {
    var session = _currentSession();
    if (session != null) return session;

    final deadline = DateTime.now().add(_sessionWaitBudget);
    while (session == null && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(_sessionPollInterval);
      session = _currentSession();
    }
    return session;
  }

  /// Récupère un 401 avec au plus [_maxAuthReplays] rejeux et un seul refresh.
  ///
  /// Le token réellement rejeté pilote toute la décision : si une autre requête
  /// a déjà publié un JWT différent, on le rejoue sans relancer de refresh —
  /// c'est le cas typique d'un 401 arrivé en retard après qu'un voisin a déjà
  /// fait tourner la session. Une fois le token stable et toujours rejeté, la
  /// session est réellement morte : on signale l'expiration, **une fois**.
  ///
  /// Un rejeu ne repasse jamais ici ([_authRecoveryRequestFlag]) : la boucle
  /// est le seul ordonnanceur, donc le nombre de requêtes est borné.
  Future<Response<dynamic>> _recoverUnauthorized(DioException error) async {
    final options = error.requestOptions;
    var rejectedToken = options.extra[_sentAccessTokenKey] as String?;

    for (var attempt = 0; attempt < _maxAuthReplays; attempt++) {
      // Seule la première passe a le droit de déclencher le single-flight ;
      // les suivantes se contentent d'un token déjà publié par un autre acteur.
      final candidate = attempt == 0
          ? await _refreshedSessionOtherThan(rejectedToken)
          : _sessionOtherThan(rejectedToken);
      if (candidate == null) break;

      try {
        return await _replay(options, candidate.accessToken);
      } on DioException catch (replayError) {
        // Un échec non-401 ne dit rien de la session : il remonte tel quel.
        if (replayError.response?.statusCode != 401) rethrow;
        rejectedToken = candidate.accessToken;
        error = replayError;
      }
    }

    if (onAuthError != null) {
      // ignore: avoid_print
      print(
          '⛔️ ApiClient: token stable encore rejeté après rejeu borné (${options.path}) — déclenchement onAuthError.');
      onAuthError!(401);
    }
    throw error;
  }

  /// Session courante valide dont le token diffère de [rejectedToken] — `null`
  /// si le seul token disponible est justement celui que le backend refuse.
  Session? _sessionOtherThan(String? rejectedToken) {
    final session = _currentSession();
    if (session == null || session.isExpired) return null;
    return session.accessToken == rejectedToken ? null : session;
  }

  /// Idem, en déclenchant au besoin le refresh single-flight.
  ///
  /// La relecture finale couvre les deux issues où le refresh ne rend pas
  /// lui-même le bon token : il a échoué alors que le SDK venait de publier sa
  /// propre session, ou il a rendu le token déjà rejeté.
  Future<Session?> _refreshedSessionOtherThan(String? rejectedToken) async {
    final alreadyPublished = _sessionOtherThan(rejectedToken);
    if (alreadyPublished != null) return alreadyPublished;

    Session? refreshed;
    try {
      // Pas de `timeout:` explicite : `SessionRefresher` calcule un budget
      // adaptatif (8 s au premier plan, 20 s au cold boot / réveil). Les 5 s
      // fixes d'avant expiraient systématiquement au réveil par tap widget,
      // ce qui armait le logout.
      refreshed = await SessionRefresher.instance.refresh();
    } catch (_) {
      // `SessionRefresher` a déjà attendu sa fenêtre de grâce ; la relecture
      // ci-dessous suffit à couvrir une publication de dernière seconde.
    }
    if (refreshed != null &&
        !refreshed.isExpired &&
        refreshed.accessToken != rejectedToken) {
      return refreshed;
    }
    return _sessionOtherThan(rejectedToken);
  }

  Future<Response<dynamic>> _replay(RequestOptions options, String token) {
    options.headers['Authorization'] = 'Bearer $token';
    options.extra[_sentAccessTokenKey] = token;
    options.extra[_authRecoveryRequestFlag] = true;
    return _dio.fetch<dynamic>(options);
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

  /// `true` quand une session Supabase est disponible à l'instant T. Permet
  /// aux caches applicatifs de ne pas mémoriser une réponse obtenue en
  /// anonyme (cf. `FeedRepository._defaultViewLastResult`).
  bool get hasSession => _currentSession() != null;

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
