import 'dart:async';

import 'package:flutter/foundation.dart';
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
/// `currentSession` avant de propager l'erreur — un autre acteur a peut-être
/// déjà obtenu une session valide.
class SessionRefresher {
  SessionRefresher._();

  static final SessionRefresher instance = SessionRefresher._();

  Completer<Session?>? _inflight;

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

  /// Refresh single-flight. Si un appel est déjà en cours, retourne sa future.
  Future<Session?> refresh({
    Duration timeout = const Duration(seconds: 8),
  }) {
    final pending = _inflight;
    if (pending != null) {
      debugPrint('SessionRefresher: piggyback on in-flight refresh.');
      return pending.future;
    }

    final completer = Completer<Session?>();
    _inflight = completer;
    _runRefresh(completer, timeout);
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
      // Le SDK a peut-être déjà obtenu une session fraîche via son propre
      // autoRefreshToken interne. On relit avant de propager l'erreur.
      final fresh = currentFn();
      if (fresh != null && !fresh.isExpired) {
        debugPrint(
            'SessionRefresher: refresh threw but currentSession is valid — recovered.');
        unawaited(PostHogService().capture(
          event: 'auth_refresh_recovered',
          properties: {'exception': e.runtimeType.toString()},
        ));
        completer.complete(fresh);
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

  @visibleForTesting
  void resetForTest() {
    _inflight = null;
    refreshFnOverride = null;
    currentSessionFnOverride = null;
  }
}
