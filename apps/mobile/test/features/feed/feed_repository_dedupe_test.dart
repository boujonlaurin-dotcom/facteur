import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:facteur/core/api/api_client.dart';
import 'package:facteur/features/feed/repositories/feed_repository.dart';

/// R5.1 — single-flight + short-window dedupe on `FeedRepository.getFeedWithRaw`
/// for the default page-1 view.
///
/// Background: the mobile app fires `/api/feed/?page=1` 2-3 × per session
/// (preload provider + cache hit silent revalidation + tab focus). The static
/// dedupe window collapses bursts within 5 s into a single network call,
/// while explicit pull-to-refresh (`forceFresh: true`) still produces a
/// real round-trip. See `docs/bugs/bug-infinite-load-requests.md` Round 5.
class _MockApiClient extends Mock implements ApiClient {}

class _MockDio extends Mock implements Dio {}

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    // Each test starts with a clean dedupe state; the static cache otherwise
    // bleeds across tests.
    FeedRepository.clearDefaultViewCache();
  });

  Map<String, dynamic> _samplePayload({int items = 3, bool hasNext = false}) {
    return {
      'items': List.generate(items, (i) => {'id': 'c$i'}),
      'pagination': {'has_next': hasNext, 'total': items},
    };
  }

  Response<dynamic> _resp(Map<String, dynamic> data) {
    return Response(
      data: data,
      statusCode: 200,
      requestOptions: RequestOptions(path: 'feed/'),
    );
  }

  test('two concurrent default-view calls share the same Future (single-flight)',
      () async {
    final api = _MockApiClient();
    final dio = _MockDio();
    when(() => api.dio).thenReturn(dio);

    int calls = 0;
    when(() => dio.get<dynamic>(any(),
        queryParameters: any(named: 'queryParameters'))).thenAnswer(
      (_) async {
        calls += 1;
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return _resp(_samplePayload());
      },
    );

    final repo = FeedRepository(api);

    // Fire two calls back-to-back, before the first completes.
    final f1 = repo.getFeedWithRaw();
    final f2 = repo.getFeedWithRaw();

    final r1 = await f1;
    final r2 = await f2;

    expect(calls, 1, reason: 'single-flight must collapse concurrent calls');
    // Both returned values come from the same parsed payload.
    expect(r1.feed.items.length, 3);
    expect(r2.feed.items.length, 3);
    // The raw payload reference is identical because both share the
    // same in-flight Future result.
    expect(identical(r1.raw, r2.raw), isTrue);
  });

  test('a follow-up default-view call within the dedupe window reuses the result',
      () async {
    final api = _MockApiClient();
    final dio = _MockDio();
    when(() => api.dio).thenReturn(dio);

    int calls = 0;
    when(() => dio.get<dynamic>(any(),
        queryParameters: any(named: 'queryParameters'))).thenAnswer(
      (_) async {
        calls += 1;
        return _resp(_samplePayload());
      },
    );

    final repo = FeedRepository(api);
    await repo.getFeedWithRaw();
    expect(calls, 1);

    // Immediate follow-up: must not hit the network.
    await repo.getFeedWithRaw();
    expect(calls, 1, reason: 'follow-up within window must reuse cached result');
  });

  test('forceFresh bypasses the dedupe window (pull-to-refresh)', () async {
    final api = _MockApiClient();
    final dio = _MockDio();
    when(() => api.dio).thenReturn(dio);

    int calls = 0;
    when(() => dio.get<dynamic>(any(),
        queryParameters: any(named: 'queryParameters'))).thenAnswer(
      (_) async {
        calls += 1;
        return _resp(_samplePayload());
      },
    );

    final repo = FeedRepository(api);
    await repo.getFeedWithRaw();
    expect(calls, 1);

    await repo.getFeedWithRaw(forceFresh: true);
    expect(calls, 2,
        reason: 'forceFresh must always produce a real network call');
  });

  test('filtered views are NOT deduplicated (each call is independent)',
      () async {
    final api = _MockApiClient();
    final dio = _MockDio();
    when(() => api.dio).thenReturn(dio);

    int calls = 0;
    when(() => dio.get<dynamic>(any(),
        queryParameters: any(named: 'queryParameters'))).thenAnswer(
      (_) async {
        calls += 1;
        return _resp(_samplePayload());
      },
    );

    final repo = FeedRepository(api);
    await repo.getFeedWithRaw(theme: 'tech');
    await repo.getFeedWithRaw(theme: 'tech');
    expect(calls, 2);
  });

  test('pagination (page > 1) is NOT deduplicated', () async {
    final api = _MockApiClient();
    final dio = _MockDio();
    when(() => api.dio).thenReturn(dio);

    int calls = 0;
    when(() => dio.get<dynamic>(any(),
        queryParameters: any(named: 'queryParameters'))).thenAnswer(
      (_) async {
        calls += 1;
        return _resp(_samplePayload());
      },
    );

    final repo = FeedRepository(api);
    await repo.getFeedWithRaw(page: 2);
    await repo.getFeedWithRaw(page: 2);
    expect(calls, 2);
  });

  test('a failure during in-flight does not poison subsequent calls',
      () async {
    final api = _MockApiClient();
    final dio = _MockDio();
    when(() => api.dio).thenReturn(dio);

    int calls = 0;
    when(() => dio.get<dynamic>(any(),
        queryParameters: any(named: 'queryParameters'))).thenAnswer(
      (_) async {
        calls += 1;
        if (calls == 1) {
          throw DioException(
            requestOptions: RequestOptions(path: 'feed/'),
            type: DioExceptionType.connectionTimeout,
          );
        }
        return _resp(_samplePayload());
      },
    );

    final repo = FeedRepository(api);
    await expectLater(repo.getFeedWithRaw(), throwsA(isA<DioException>()));

    // The next call must produce a fresh network attempt, not be stuck on
    // the failed Future.
    final ok = await repo.getFeedWithRaw();
    expect(ok.feed.items.length, 3);
    expect(calls, 2);
  });

  test('clearDefaultViewCache resets state (logout safety)', () async {
    final api = _MockApiClient();
    final dio = _MockDio();
    when(() => api.dio).thenReturn(dio);

    int calls = 0;
    when(() => dio.get<dynamic>(any(),
        queryParameters: any(named: 'queryParameters'))).thenAnswer(
      (_) async {
        calls += 1;
        return _resp(_samplePayload());
      },
    );

    final repo = FeedRepository(api);
    await repo.getFeedWithRaw();
    expect(calls, 1);

    FeedRepository.clearDefaultViewCache();

    await repo.getFeedWithRaw();
    expect(calls, 2,
        reason: 'cleared state must not serve a stale cached result');
  });
}
