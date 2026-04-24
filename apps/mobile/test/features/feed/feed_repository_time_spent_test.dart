import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:facteur/core/api/api_client.dart';
import 'package:facteur/features/feed/repositories/feed_repository.dart';

/// Sprint 1.1 — PATCH `time_spent_seconds` on `user_content_status`.
/// Ensures the mobile repository POSTs the accumulated reading duration
/// (capped at 1800s) to `/contents/{id}/status` so the recommendation
/// feedback loop receives the signal.
class _MockApiClient extends Mock implements ApiClient {}

class _MockDio extends Mock implements Dio {}

void main() {
  setUpAll(() {
    registerFallbackValue(RequestOptions(path: ''));
    registerFallbackValue(<String, dynamic>{});
  });

  Response<void> _ok() => Response<void>(
        requestOptions: RequestOptions(path: 'contents/x/status'),
        statusCode: 200,
      );

  test('posts time_spent_seconds payload to /contents/{id}/status', () async {
    final api = _MockApiClient();
    final dio = _MockDio();
    when(() => api.dio).thenReturn(dio);

    Map<String, dynamic>? capturedData;
    String? capturedPath;
    when(() => dio.post<void>(any(), data: any(named: 'data'))).thenAnswer(
      (invocation) async {
        capturedPath = invocation.positionalArguments.first as String;
        capturedData =
            invocation.namedArguments[#data] as Map<String, dynamic>?;
        return _ok();
      },
    );

    final repo = FeedRepository(api);
    await repo.updateContentStatusWithTimeSpent('article-1', 42);

    expect(capturedPath, 'contents/article-1/status');
    expect(capturedData, {'time_spent_seconds': 42});
  });

  test('caps the payload at 1800 seconds (30 min)', () async {
    final api = _MockApiClient();
    final dio = _MockDio();
    when(() => api.dio).thenReturn(dio);

    Map<String, dynamic>? capturedData;
    when(() => dio.post<void>(any(), data: any(named: 'data'))).thenAnswer(
      (invocation) async {
        capturedData =
            invocation.namedArguments[#data] as Map<String, dynamic>?;
        return _ok();
      },
    );

    final repo = FeedRepository(api);
    await repo.updateContentStatusWithTimeSpent('article-2', 7200);

    expect(capturedData?['time_spent_seconds'], 1800);
  });

  test('skips the network call when duration is zero or negative', () async {
    final api = _MockApiClient();
    final dio = _MockDio();
    when(() => api.dio).thenReturn(dio);

    final repo = FeedRepository(api);
    await repo.updateContentStatusWithTimeSpent('article-3', 0);
    await repo.updateContentStatusWithTimeSpent('article-3', -5);

    verifyNever(() => dio.post<void>(any(), data: any(named: 'data')));
  });

  test('swallows Dio errors (fire-and-forget)', () async {
    final api = _MockApiClient();
    final dio = _MockDio();
    when(() => api.dio).thenReturn(dio);
    when(() => dio.post<void>(any(), data: any(named: 'data'))).thenThrow(
      DioException(requestOptions: RequestOptions(path: 'x')),
    );

    final repo = FeedRepository(api);
    await expectLater(
      repo.updateContentStatusWithTimeSpent('article-4', 30),
      completes,
    );
  });
}
