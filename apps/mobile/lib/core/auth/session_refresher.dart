import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/posthog_service.dart';

/// Signature injectable pour le refresh — facilite les tests unitaires.
typedef RefreshSessionFn = Future<Session?> Function();

/// Signature injectable pour la lecture de la session courante.
typedef CurrentSessionFn = Session? Function();

/// Coordonne tous les `refreshSession()` de l'app pour éviter la race
/// "double-refresh" sur les refresh tokens single-use de Supabase.
///
/// **Pourquoi** : Supabase utilise des refresh tokens en mode rotation
/// single-use. Chaque refresh révoque l'ancien et émet un nouveau. Si deux
/// refresh partent en parallèle avec le même token, le 2ème reçoit une
/// `AuthException` ("session_not_found", "Already Used", "invalid refresh
/// token") — ce qui faisait déconnecter l'utilisateur. Cf.
/// `docs/bugs/bug-android-disconnect-race.md`.
///
/// **Garantie** : un seul appel SDK en vol à la fois. Tous les callers
/// concurrents reçoivent la même `Session?`.
///
/// Si le SDK lance malgré tout une `AuthException` (ex. son propre
/// `autoRefreshToken` interne a déjà consommé le token), on relit
/// `currentSession` pendant une courte fenêtre bornée avant de propager
/// l'erreur — un autre acteur a peut-être déjà obtenu une session valide, et sa
/// publication arrive parfois juste après l'exception.
class SessionRefresher {
  SessionRefresher._();

  static final SessionRefresher instance = SessionRefresher._();

  Completer<Session?>? _inflight;

  /// Fenêtre pendant laquelle le SDK peut encore publier la session obtenue
  /// par son auto-refresh après que notre appel a échoué (notamment
  /// `Already Used`). Le polling reste volontairement court et borné.
  static const Duration _recoveryGracePeriod = Duration(milliseconds: 500);
  static const Duration _recoveryPollInterval = Duration(milliseconds: 50);

  /// Hooks injectables pour les tests. En production, défauts = SDK Supabase.
  @visibleForTesting
  RefreshSessionFn? refreshFnOverride;
  @visibleForTesting
  CurrentSessionFn? currentSessionFnOverride;

  Future<Session?> _defaultRefresh(Duration timeout) async {
    final response = await Supabase.instance.client.auth
        .refreshSession()
        .timeout(timeout);
    return response.session;
  }

  Session? _defaultCurrentSession() =>
      Supabase.instance.client.auth.currentSession;

  /// Budget d'attente par défaut d'un `refreshSession()`.
  ///
  /// 8 s suffisent quand l'app est au premier plan sur un réseau correct. Au
  /// cold boot ou au retour de `paused` (app réveillée par un tap widget, radio
  /// cellulaire endormie), le handshake dépasse régulièrement ce plafond : le
  /// `TimeoutException 0:00:08` est Sentry FLUTTER-6, et son échec en cascade
  /// arme `onAuthError(401)` → déconnexion. Même approche que
  /// `resolveMorningRitualMaxWait` : on élargit le budget hors `resumed`.
  ///
  /// Exposé pour les tests.
  @visibleForTesting
  static Duration resolveRefreshTimeout(AppLifecycleState? lifecycle) {
    return lifecycle == AppLifecycleState.resumed
        ? const Duration(seconds: 8)
        : const Duration(seconds: 20);
  }

  Duration get _defaultTimeout {
    AppLifecycleState? lifecycle;
    try {
      lifecycle = WidgetsBinding.instance.lifecycleState;
    } catch (_) {
      // Binding non initialisé (tests unitaires purs, isolate de fond) : on
      // retombe sur le budget « premier plan », le plus serré.
      lifecycle = AppLifecycleState.resumed;
    }
    return resolveRefreshTimeout(lifecycle);
  }

  /// Refresh single-flight. Si un appel est déjà en cours, retourne sa future.
  /// [timeout] omis → budget adaptatif ([resolveRefreshTimeout]).
  Future<Session?> refresh({Duration? timeout}) {
    final budget = timeout ?? _defaultTimeout;
    final pending = _inflight;
    if (pending != null) {
      debugPrint('SessionRefresher: piggyback on in-flight refresh.');
      return pending.future;
    }

    final completer = Completer<Session?>();
    _inflight = completer;
    _runRefresh(completer, budget);
    return completer.future;
  }

  Future<void> _runRefresh(
    Completer<Session?> completer,
    Duration timeout,
  ) async {
    final refreshFn = refreshFnOverride ?? () => _defaultRefresh(timeout);
    final currentFn = currentSessionFnOverride ?? _defaultCurrentSession;
    unawaited(PostHogService().capture(event: 'auth_refresh_attempt'));
    try {
      debugPrint('SessionRefresher: starting refreshSession()...');
      final session = await refreshFn();
      debugPrint('SessionRefresher: ✅ refresh OK.');
      unawaited(PostHogService().capture(event: 'auth_refresh_success'));
      completer.complete(session);
    } catch (e, st) {
      // Le SDK a peut-être déjà consommé le refresh token via son propre
      // autoRefreshToken. La publication de `currentSession` peut arriver
      // légèrement après l'exception : on lui laisse une courte fenêtre au
      // lieu de conclure instantanément à une déconnexion.
      final recovered = await _awaitValidCurrentSession(currentFn);
      if (recovered != null) {
        debugPrint(
            'SessionRefresher: refresh threw but currentSession is valid — recovered.');
        unawaited(PostHogService().capture(
          event: 'auth_refresh_recovered',
          properties: {'exception': e.runtimeType.toString()},
        ));
        completer.complete(recovered);
      } else {
        debugPrint('SessionRefresher: ❌ refresh failed: $e');
        unawaited(PostHogService().capture(
          event: 'auth_refresh_failure',
          properties: {'exception': e.runtimeType.toString()},
        ));
        unawaited(Sentry.captureException(e, stackTrace: st));
        completer.completeError(e, st);
      }
    } finally {
      _inflight = null;
    }
  }

  Future<Session?> _awaitValidCurrentSession(CurrentSessionFn currentFn) async {
    final deadline = DateTime.now().add(_recoveryGracePeriod);
    while (true) {
      final session = currentFn();
      if (session != null && !session.isExpired) return session;
      if (!DateTime.now().isBefore(deadline)) return null;
      await Future<void>.delayed(_recoveryPollInterval);
    }
  }

  @visibleForTesting
  void resetForTest() {
    _inflight = null;
    refreshFnOverride = null;
    currentSessionFnOverride = null;
  }
}
