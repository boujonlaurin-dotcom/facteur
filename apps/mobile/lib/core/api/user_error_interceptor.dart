import 'package:dio/dio.dart';

import '../errors/user_facing_error_notifier.dart';

/// Clé `extra` Dio qui opt-in un appel à la remontée « souci côté device ».
/// Posée par les repositories sur les appels déclenchés par un tap explicite,
/// lue par [UserErrorInterceptor]. Constante partagée = anti-typo.
const String kUserFacingExtraKey = 'userFacing';

/// Interceptor Dio (dernier de la chaîne, après [RetryInterceptor]) qui remonte
/// à l'utilisateur **uniquement** les erreurs d'un appel explicitement marqué
/// `extra['userFacing'] == true` — c.-à-d. déclenché par un tap, pas un fetch
/// de fond. Tout le reste continue à filer chez Sentry en silence.
///
/// Ne bloque jamais la chaîne : il notifie puis relaie l'erreur telle quelle.
class UserErrorInterceptor extends Interceptor {
  UserErrorInterceptor({UserFacingErrorNotifier? notifier})
      : _notifier = notifier ?? UserFacingErrorNotifier.instance;

  final UserFacingErrorNotifier _notifier;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final source = _classify(err);
    final userFacing = err.requestOptions.extra[kUserFacingExtraKey] == true;
    if (source != null && userFacing) {
      final route = err.requestOptions.path;
      final statusPart = err.response?.statusCode?.toString() ?? err.type.name;
      // fire-and-forget : la logique de cooldown vit dans le notifier.
      _notifier.report(
        source: source,
        signature: '${source.tag}|$statusPart|$route',
        route: route,
        detail: statusPart,
      );
    }
    handler.next(err);
  }

  /// Mappe une DioException vers une source whitelistée, ou `null` si elle ne
  /// doit jamais remonter à l'utilisateur (4xx, 401, annulation, etc.).
  UserErrorSource? _classify(DioException err) {
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return UserErrorSource.timeout;
      case DioExceptionType.badResponse:
        final code = err.response?.statusCode;
        if (code != null && code >= 500 && code < 600) {
          return UserErrorSource.http5xx;
        }
        return null;
      default:
        return null;
    }
  }
}
