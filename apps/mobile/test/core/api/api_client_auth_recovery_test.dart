import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:facteur/core/api/api_client.dart';
import 'package:facteur/core/auth/session_refresher.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

typedef _ResponseStatus = FutureOr<int> Function(RequestOptions options);

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this._responseStatus);

  final _ResponseStatus _responseStatus;
  final List<String?> authorizationHeaders = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    authorizationHeaders.add(options.headers['Authorization'] as String?);
    final status = await _responseStatus(options);
    return ResponseBody.fromString(
      jsonEncode(status == 200 ? {'ok': true} : {'detail': 'unauthorized'}),
      status,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Session makeSession(String accessToken, {bool expired = false}) {
    final session = Session(
      accessToken: accessToken,
      tokenType: 'bearer',
      refreshToken: 'refresh-token',
      user: User(
        id: 'user-1',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
      ),
    );
    session.expiresAt = DateTime.now()
            .add(Duration(hours: expired ? -1 : 1))
            .millisecondsSinceEpoch ~/
        1000;
    return session;
  }

  late Session? currentSession;
  late List<int> authErrors;
  late _MockSupabaseClient supabase;

  ApiClient makeClient(_RecordingAdapter adapter) => ApiClient(
        supabase,
        baseUrl: 'https://api.test/',
        currentSessionFnOverride: () => currentSession,
        sessionWaitBudget: Duration.zero,
        httpClientAdapter: adapter,
        onAuthError: authErrors.add,
      );

  setUp(() {
    SessionRefresher.instance.resetForTest();
    currentSession = null;
    authErrors = [];
    supabase = _MockSupabaseClient();
  });

  tearDown(() {
    SessionRefresher.instance.resetForTest();
  });

  test('5 appels 401 parallèles partagent un refresh et le même nouveau JWT',
      () async {
    final expired = makeSession('token-old-12345', expired: true);
    final fresh = makeSession('token-fresh-12345');
    currentSession = expired;
    var oldRequests = 0;
    final allOldRequestsArrived = Completer<void>();
    final adapter = _RecordingAdapter((options) async {
      final authorization = options.headers['Authorization'];
      if (authorization == 'Bearer ${expired.accessToken}') {
        oldRequests += 1;
        if (oldRequests == 5) allOldRequestsArrived.complete();
        await allOldRequestsArrived.future;
        return 401;
      }
      return authorization == 'Bearer ${fresh.accessToken}' ? 200 : 401;
    });
    var refreshCalls = 0;
    SessionRefresher.instance.refreshFnOverride = () async {
      refreshCalls += 1;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      currentSession = fresh;
      return fresh;
    };
    SessionRefresher.instance.currentSessionFnOverride = () => currentSession;
    final client = makeClient(adapter);

    final results = await Future.wait(
      List.generate(5, (_) => client.get('protected')),
    );

    expect(results, everyElement({'ok': true}));
    expect(refreshCalls, 1);
    expect(
      adapter.authorizationHeaders
          .where((header) => header == 'Bearer ${fresh.accessToken}'),
      hasLength(5),
    );
    expect(authErrors, isEmpty);
  });

  test('401 retardé utilise le token courant sans second refresh', () async {
    final old = makeSession('token-old-12345');
    final fresh = makeSession('token-fresh-12345');
    currentSession = old;
    final oldRequestArrived = Completer<void>();
    final releaseOldResponse = Completer<void>();
    final adapter = _RecordingAdapter((options) async {
      if (options.headers['Authorization'] == 'Bearer ${old.accessToken}') {
        oldRequestArrived.complete();
        await releaseOldResponse.future;
        return 401;
      }
      return 200;
    });
    var refreshCalls = 0;
    SessionRefresher.instance.refreshFnOverride = () async {
      refreshCalls += 1;
      return fresh;
    };
    final client = makeClient(adapter);

    final request = client.get('protected');
    await oldRequestArrived.future;
    currentSession = fresh;
    releaseOldResponse.complete();

    expect(await request, {'ok': true});
    expect(refreshCalls, 0);
    expect(adapter.authorizationHeaders, [
      'Bearer ${old.accessToken}',
      'Bearer ${fresh.accessToken}',
    ]);
    expect(authErrors, isEmpty);
  });

  test(
      'deuxième 401 autorise un dernier replay seulement avec token plus récent',
      () async {
    final old = makeSession('token-old-12345', expired: true);
    final refreshed = makeSession('token-fresh-12345');
    final newest = makeSession('token-newest-12345');
    currentSession = old;
    final adapter = _RecordingAdapter((options) {
      final authorization = options.headers['Authorization'];
      if (authorization == 'Bearer ${refreshed.accessToken}') {
        currentSession = newest;
        return 401;
      }
      return authorization == 'Bearer ${newest.accessToken}' ? 200 : 401;
    });
    var refreshCalls = 0;
    SessionRefresher.instance.refreshFnOverride = () async {
      refreshCalls += 1;
      currentSession = refreshed;
      return refreshed;
    };
    final client = makeClient(adapter);

    expect(await client.get('protected'), {'ok': true});
    expect(refreshCalls, 1);
    expect(adapter.authorizationHeaders, [
      'Bearer ${old.accessToken}',
      'Bearer ${refreshed.accessToken}',
      'Bearer ${newest.accessToken}',
    ]);
    expect(authErrors, isEmpty);
  });

  test('token stable encore rejeté → deux requêtes et un logout unique',
      () async {
    final old = makeSession('token-old-12345', expired: true);
    final refreshed = makeSession('token-fresh-12345');
    currentSession = old;
    final adapter = _RecordingAdapter((_) => 401);
    var refreshCalls = 0;
    SessionRefresher.instance.refreshFnOverride = () async {
      refreshCalls += 1;
      currentSession = refreshed;
      return refreshed;
    };
    final client = makeClient(adapter);

    await expectLater(
      client.get('protected'),
      throwsA(
        isA<DioException>().having(
          (error) => error.response?.statusCode,
          'statusCode',
          401,
        ),
      ),
    );

    expect(refreshCalls, 1);
    expect(adapter.authorizationHeaders, hasLength(2));
    expect(authErrors, [401]);
  });

  test('refresh échoué sans session valide → erreur et expiration uniques',
      () async {
    currentSession = makeSession('token-old-12345', expired: true);
    final adapter = _RecordingAdapter((_) => 401);
    var refreshCalls = 0;
    SessionRefresher.instance.refreshFnOverride = () async {
      refreshCalls += 1;
      throw const AuthException('refresh_token expired');
    };
    SessionRefresher.instance.currentSessionFnOverride = () => currentSession;
    final client = makeClient(adapter);

    await expectLater(client.get('protected'), throwsA(isA<DioException>()));

    expect(refreshCalls, 1);
    expect(adapter.authorizationHeaders, hasLength(1));
    expect(authErrors, [401]);
  });

  test('requête anonyme 401 → aucun refresh ni logout', () async {
    final adapter = _RecordingAdapter((_) => 401);
    var refreshCalls = 0;
    SessionRefresher.instance.refreshFnOverride = () async {
      refreshCalls += 1;
      return makeSession('token-unexpected-12345');
    };
    final client = makeClient(adapter);

    await expectLater(
        client.get('public-but-protected'), throwsA(isA<DioException>()));

    expect(refreshCalls, 0);
    expect(adapter.authorizationHeaders, [null]);
    expect(authErrors, isEmpty);
  });
}
