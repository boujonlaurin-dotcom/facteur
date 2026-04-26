import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:facteur/core/auth/session_refresher.dart';

/// Tests du `SessionRefresher` — single-flight refresh + recovery via
/// `currentSession`. Voir `docs/bugs/bug-android-disconnect-race.md`.
void main() {
  Session makeSession({String accessToken = 'tok-1', int? expiresAt}) {
    final session = Session(
      accessToken: accessToken,
      tokenType: 'bearer',
      refreshToken: 'rt-1',
      user: User(
        id: 'user-1',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
      ),
    );
    // Override le `expiresAt` (dérivé du JWT en prod) pour les tests.
    session.expiresAt =
        expiresAt ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000) + 3600;
    return session;
  }

  setUp(() {
    SessionRefresher.instance.resetForTest();
  });

  test('single-flight: 5 appels parallèles → 1 seul refresh SDK', () async {
    var calls = 0;
    final completer = Completer<Session?>();
    SessionRefresher.instance.refreshFnOverride = () async {
      calls += 1;
      return completer.future;
    };

    final futures = List.generate(
      5,
      (_) => SessionRefresher.instance.refresh(),
    );

    // Tous les callers sont en attente sur la même future, le SDK n'a été
    // appelé qu'une seule fois.
    expect(calls, 1);

    final session = makeSession();
    completer.complete(session);
    final results = await Future.wait(futures);

    expect(calls, 1, reason: 'aucun refresh additionnel après complétion');
    expect(results.every((s) => s?.accessToken == session.accessToken), isTrue);
  });

  test('après complétion, un nouveau refresh redéclenche bien le SDK',
      () async {
    var calls = 0;
    SessionRefresher.instance.refreshFnOverride = () async {
      calls += 1;
      return makeSession(accessToken: 'tok-$calls');
    };

    final s1 = await SessionRefresher.instance.refresh();
    final s2 = await SessionRefresher.instance.refresh();

    expect(calls, 2);
    expect(s1?.accessToken, 'tok-1');
    expect(s2?.accessToken, 'tok-2');
  });

  test(
      'refresh throw mais currentSession valide → completer reçoit la session récupérée',
      () async {
    final recovered = makeSession(accessToken: 'recovered');
    SessionRefresher.instance.refreshFnOverride = () async {
      throw const AuthException('Already Used');
    };
    SessionRefresher.instance.currentSessionFnOverride = () => recovered;

    final result = await SessionRefresher.instance.refresh();
    expect(result?.accessToken, 'recovered',
        reason: 'recovery via currentSession après échec du refresh');
  });

  test(
      'refresh throw + currentSession null → l\'erreur est propagée',
      () async {
    SessionRefresher.instance.refreshFnOverride = () async {
      throw const AuthException('refresh_token expired');
    };
    SessionRefresher.instance.currentSessionFnOverride = () => null;

    expect(
      () => SessionRefresher.instance.refresh(),
      throwsA(isA<AuthException>()),
    );
  });

  test(
      'refresh throw + currentSession expirée → l\'erreur est propagée',
      () async {
    final expired = makeSession(
      expiresAt: (DateTime.now().millisecondsSinceEpoch ~/ 1000) - 60,
    );
    SessionRefresher.instance.refreshFnOverride = () async {
      throw const AuthException('session_not_found');
    };
    SessionRefresher.instance.currentSessionFnOverride = () => expired;

    expect(
      () => SessionRefresher.instance.refresh(),
      throwsA(isA<AuthException>()),
    );
  });

  test(
      'pendant un refresh in-flight, les nouveaux callers piggyback même si l\'inflight rate',
      () async {
    final completer = Completer<Session?>();
    SessionRefresher.instance.refreshFnOverride = () => completer.future;
    SessionRefresher.instance.currentSessionFnOverride =
        () => makeSession(accessToken: 'recovered');

    final f1 = SessionRefresher.instance.refresh();
    final f2 = SessionRefresher.instance.refresh();

    completer.completeError(const AuthException('Already Used'));

    final r1 = await f1;
    final r2 = await f2;
    expect(r1?.accessToken, 'recovered');
    expect(r2?.accessToken, 'recovered',
        reason: 'le 2e caller piggyback sur la même future, recover identique');
  });
}
