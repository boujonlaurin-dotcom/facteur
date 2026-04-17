import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:facteur/core/api/api_client.dart';
import 'package:facteur/core/services/analytics_service.dart';
import 'package:facteur/core/services/posthog_service.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockDio extends Mock implements Dio {}

class _RecordingPostHog extends PostHogService {
  final List<({String event, Map<String, Object>? properties})> captured = [];
  bool _enabled = true;

  @override
  bool get isEnabled => _enabled;

  void setEnabled(bool v) => _enabled = v;

  @override
  Future<void> capture({
    required String event,
    Map<String, Object>? properties,
  }) async {
    captured.add((event: event, properties: properties));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});

  late _MockApiClient api;
  late _MockDio dio;
  late _RecordingPostHog posthog;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    api = _MockApiClient();
    dio = _MockDio();
    when(() => api.dio).thenReturn(dio);
    when(
      () => dio.post(any(), data: any(named: 'data')),
    ).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: ''),
        statusCode: 201,
      ),
    );
    posthog = _RecordingPostHog();
  });

  test('startSession mirrors session_start to app_open on PostHog', () async {
    final service = AnalyticsService(api, posthog: posthog);
    await service.startSession(isOrganic: true);

    expect(posthog.captured.map((e) => e.event), contains('app_open'));
    // Backend logging still happens.
    verify(
      () => dio.post('analytics/events', data: any(named: 'data')),
    ).called(1);
  });

  test('content_interaction read >30s emits article_read + article_completed',
      () async {
    final service = AnalyticsService(api, posthog: posthog);
    await service.trackContentInteraction(
      action: 'read',
      surface: 'digest',
      contentId: 'c1',
      sourceId: 's1',
      timeSpentSeconds: 45,
    );

    final events = posthog.captured.map((e) => e.event).toList();
    expect(events, containsAll(<String>['article_read', 'article_completed']));
  });

  test('content_interaction read <30s emits article_read but NOT completed',
      () async {
    final service = AnalyticsService(api, posthog: posthog);
    await service.trackContentInteraction(
      action: 'read',
      surface: 'digest',
      contentId: 'c1',
      sourceId: 's1',
      timeSpentSeconds: 12,
    );

    final events = posthog.captured.map((e) => e.event).toList();
    expect(events, contains('article_read'));
    expect(events, isNot(contains('article_completed')));
  });

  test('save action does not emit article_read', () async {
    final service = AnalyticsService(api, posthog: posthog);
    await service.trackContentInteraction(
      action: 'save',
      surface: 'feed',
      contentId: 'c1',
      sourceId: 's1',
    );

    expect(posthog.captured, isEmpty);
  });

  test('trackSourceAdd fires source_added on PostHog', () async {
    final service = AnalyticsService(api, posthog: posthog);
    await service.trackSourceAdd('source-42');

    expect(
      posthog.captured.map((e) => e.event),
      contains('source_added'),
    );
  });

  test('trackComparisonViewed fires comparison_viewed on PostHog', () async {
    final service = AnalyticsService(api, posthog: posthog);
    await service.trackComparisonViewed(clusterId: 'k-1', sourcesCount: 5);

    final entry = posthog.captured.firstWhere(
      (e) => e.event == 'comparison_viewed',
    );
    expect(entry.properties?['cluster_id'], 'k-1');
    expect(entry.properties?['sources_count'], 5);
  });

  test('PostHog disabled → no captures but backend still called', () async {
    posthog.setEnabled(false);
    final service = AnalyticsService(api, posthog: posthog);

    await service.trackSourceAdd('src');
    await service.trackContentInteraction(
      action: 'read',
      surface: 'feed',
      contentId: 'c',
      sourceId: 's',
      timeSpentSeconds: 60,
    );

    expect(posthog.captured, isEmpty);
    verify(
      () => dio.post('analytics/events', data: any(named: 'data')),
    ).called(2);
  });

  test('backend failure does not crash analytics layer', () async {
    when(() => dio.post(any(), data: any(named: 'data')))
        .thenThrow(DioException(requestOptions: RequestOptions(path: '')));

    final service = AnalyticsService(api, posthog: posthog);
    // Must not throw
    await service.trackSourceAdd('src');
    // PostHog still fired (independent of backend).
    expect(posthog.captured.map((e) => e.event), contains('source_added'));
  });
}
