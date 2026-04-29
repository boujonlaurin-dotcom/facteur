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

  @override
  bool get isEnabled => true;

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
  final postedPayloads = <Map<String, dynamic>>[];

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    postedPayloads.clear();
    api = _MockApiClient();
    dio = _MockDio();
    when(() => api.dio).thenReturn(dio);
    when(
      () => dio.post(any(), data: any(named: 'data')),
    ).thenAnswer((inv) async {
      final data = inv.namedArguments[const Symbol('data')];
      if (data is Map<String, dynamic>) postedPayloads.add(data);
      return Response(
        requestOptions: RequestOptions(path: ''),
        statusCode: 201,
      );
    });
    posthog = _RecordingPostHog();
  });

  test('trackDigestOpened emits digest_opened on backend + PostHog', () async {
    final service = AnalyticsService(api, posthog: posthog);
    await service.trackDigestOpened(digestDate: '2026-04-24', itemsCount: 7);

    expect(postedPayloads.single['event_type'], 'digest_opened');
    expect(posthog.captured.map((e) => e.event), contains('digest_opened'));
  });

  test('trackDigestItemViewed is backend-only (no PostHog mirror)', () async {
    final service = AnalyticsService(api, posthog: posthog);
    await service.trackDigestItemViewed(
      digestDate: '2026-04-24',
      contentId: 'c1',
      position: 2,
    );

    expect(postedPayloads.single['event_type'], 'digest_item_viewed');
    expect(posthog.captured, isEmpty);
  });

  test('trackPerspectiveComparisonOpened fires on backend + PostHog', () async {
    final service = AnalyticsService(api, posthog: posthog);
    await service.trackPerspectiveComparisonOpened(
      contentId: 'c1',
      clusterId: 'k1',
      sourcesCount: 4,
    );

    expect(
      postedPayloads.single['event_type'],
      'perspective_comparison_opened',
    );
    expect(
      posthog.captured.map((e) => e.event),
      contains('perspective_comparison_opened'),
    );
  });

  test('trackPerspectiveArticleViewed + closed are backend-only', () async {
    final service = AnalyticsService(api, posthog: posthog);
    await service.trackPerspectiveArticleViewed(
      contentId: 'c1',
      perspectiveArticleId: 'p1',
    );
    await service.trackPerspectiveComparisonClosed(
      contentId: 'c1',
      viewedArticles: 2,
      openedSeconds: 14,
    );

    expect(
      postedPayloads.map((p) => p['event_type']),
      containsAll(<String>[
        'perspective_article_viewed',
        'perspective_comparison_closed',
      ]),
    );
    expect(posthog.captured, isEmpty);
  });

  test('trackArticleFeedbackSubmitted carries origin + extra props', () async {
    final service = AnalyticsService(api, posthog: posthog);
    await service.trackArticleFeedbackSubmitted(
      contentId: 'c1',
      feedbackType: 'not_interested',
      origin: 'feed',
      extra: {'reason': 'off_topic'},
    );

    final payload = postedPayloads.single;
    expect(payload['event_type'], 'article_feedback_submitted');
    final data = payload['event_data'] as Map<String, dynamic>;
    expect(data['origin'], 'feed');
    expect(data['feedback_type'], 'not_interested');
    expect(data['reason'], 'off_topic');
    expect(
      posthog.captured.map((e) => e.event),
      contains('article_feedback_submitted'),
    );
  });

  test('subtopic events — added mirrors to PostHog, shown/removed do not',
      () async {
    final service = AnalyticsService(api, posthog: posthog);
    await service.trackSubtopicSuggestionShown(
      subtopicSlug: 'mobilite',
      origin: 'onboarding',
    );
    await service.trackSubtopicAdded(
      subtopicSlug: 'mobilite',
      origin: 'onboarding',
    );
    await service.trackSubtopicRemoved(
      subtopicSlug: 'mobilite',
      origin: 'custom_topics',
    );

    expect(
      postedPayloads.map((p) => p['event_type']),
      containsAll(<String>[
        'subtopic_suggestion_shown',
        'subtopic_added',
        'subtopic_removed',
      ]),
    );
    expect(posthog.captured.map((e) => e.event), equals(['subtopic_added']));
  });

  test('trackPreferenceChanged stringifies old/new values uniformly',
      () async {
    final service = AnalyticsService(api, posthog: posthog);
    await service.trackPreferenceChanged(
      key: 'notifications_daily_digest',
      oldValue: false,
      newValue: true,
    );

    final data = postedPayloads.single['event_data'] as Map<String, dynamic>;
    expect(data['key'], 'notifications_daily_digest');
    expect(data['old_value'], 'false');
    expect(data['new_value'], 'true');
    expect(
      posthog.captured.map((e) => e.event),
      contains('preference_changed'),
    );
  });

  test('trackPreferenceChanged handles null values (first write)', () async {
    final service = AnalyticsService(api, posthog: posthog);
    await service.trackPreferenceChanged(
      key: 'digest_target_time',
      oldValue: null,
      newValue: '07:30',
    );

    final data = postedPayloads.single['event_data'] as Map<String, dynamic>;
    expect(data['old_value'], isNull);
    expect(data['new_value'], '07:30');
  });

  // ── Story 14.3 — Well-informed self-report NPS events ──────────────

  test('trackWellInformedPromptShown is backend-only (no PostHog)', () async {
    final service = AnalyticsService(api, posthog: posthog);
    await service.trackWellInformedPromptShown();

    expect(postedPayloads.single['event_type'], 'well_informed_prompt_shown');
    final data = postedPayloads.single['event_data'] as Map<String, dynamic>;
    expect(data['context'], 'digest_inline');
    expect(posthog.captured, isEmpty);
  });

  test('trackWellInformedPromptSkipped mirrors to PostHog', () async {
    final service = AnalyticsService(api, posthog: posthog);
    await service.trackWellInformedPromptSkipped();

    expect(
      postedPayloads.single['event_type'],
      'well_informed_prompt_skipped',
    );
    expect(
      posthog.captured.map((e) => e.event),
      contains('well_informed_prompt_skipped'),
    );
  });

  test('trackWellInformedScoreSubmitted emits score + context everywhere',
      () async {
    final service = AnalyticsService(api, posthog: posthog);
    await service.trackWellInformedScoreSubmitted(score: 8);

    expect(
      postedPayloads.single['event_type'],
      'well_informed_score_submitted',
    );
    final data = postedPayloads.single['event_data'] as Map<String, dynamic>;
    expect(data['score'], 8);
    expect(data['context'], 'digest_inline');
    final ph = posthog.captured.singleWhere(
      (e) => e.event == 'well_informed_score_submitted',
    );
    expect(ph.properties?['score'], 8);
  });
}
