import 'package:dio/dio.dart';

/// Interceptor Dio pour gérer les retries automatiques
class RetryInterceptor extends Interceptor {
  final Dio dio;
  final int maxRetries;
  final List<Duration> retryDelays;

  RetryInterceptor({
    required this.dio,
    this.maxRetries = 3,
    this.retryDelays = const [
      Duration(milliseconds: 500),
      Duration(seconds: 1),
      Duration(seconds: 2),
    ],
  });

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    // Vérifier si on doit retry
    if (!_shouldRetry(err)) {
      return handler.next(err);
    }

    // Récupérer le nombre de tentatives déjà faites
    final retryCount = err.requestOptions.extra['retryCount'] as int? ?? 0;

    // Si on a dépassé le max, ne pas retry
    if (retryCount >= maxRetries) {
      return handler.next(err);
    }

    // Attendre avant de retry
    final delayIndex = retryCount.clamp(0, retryDelays.length - 1);
    await Future.delayed(retryDelays[delayIndex]);

    // Incrémenter le compteur de retry
    err.requestOptions.extra['retryCount'] = retryCount + 1;

    // Logger la tentative de retry
    _logRetry(err, retryCount + 1);

    // Retry la requête
    try {
      final response = await dio.fetch(err.requestOptions);
      return handler.resolve(response);
    } on DioException catch (e) {
      return handler.next(e);
    }
  }

  /// Détermine si on doit retry selon le type d'erreur
  bool _shouldRetry(DioException err) {
    // Retry sur les erreurs de timeout
    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.sendTimeout) {
      return true;
    }

    // Retry sur les erreurs réseau
    if (err.type == DioExceptionType.connectionError) {
      return true;
    }

    // Retry sur les erreurs 5xx (serveur), sauf 503 (surcharge)
    final statusCode = err.response?.statusCode;
    if (statusCode != null && statusCode >= 500 && statusCode < 600) {
      // Ne pas retry 503 (serveur surcharge) - les retries aggravent le probleme
      if (statusCode == 503) return false;
      return true;
    }

    // Ne pas retry sur :
    // - 401 (auth) : besoin de se reconnecter
    // - 422 (validation) : données invalides
    // - 403 (forbidden) : pas de permissions
    // - 404 (not found) : ressource introuvable
    return false;
  }

  /// Logger les tentatives de retry
  void _logRetry(DioException err, int attempt) {
    // ignore: avoid_print
    print(
      'Retry attempt $attempt/$maxRetries for ${err.requestOptions.path} '
      '(${err.type})',
    );
  }
}

