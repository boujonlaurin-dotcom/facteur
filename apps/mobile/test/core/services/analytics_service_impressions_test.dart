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
  final List<String> captured = [];

  @override
  bool get isEnabled => true;

  @override
  Future<void> capture({
    required String event,
    Map<String, Object>? properties,
  }) async {
    captured.add(event);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockApiClient api;
  late _MockDio dio;
  late _RecordingPostHog posthog;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    api = _MockApiClient();
    dio = _MockDio();
    when(() => api.dio).thenReturn(dio);
    when(() => dio.post<dynamic>(any(), data: any(named: 'data'))).thenAnswer(
      (_) async =>
          Response(requestOptions: RequestOptions(path: ''), statusCode: 201),
    );
    posthog = _RecordingPostHog();
  });

  Future<void> impress(
    AnalyticsService service, {
    required String contentId,
    String sectionKey = 'theme:politique',
    String dayKey = '2026-08-02',
    int position = 0,
    double? scoreTotal,
  }) {
    return service.trackArticleImpression(
      contentId: contentId,
      sectionKey: sectionKey,
      sectionFamily: 'theme',
      surface: 'tournee',
      dayKey: dayKey,
      sectionIndex: 1,
      positionInSection: position,
      globalPosition: 5 + position,
      scoreTotal: scoreTotal,
      theme: 'politique',
      sourceId: 'source-1',
    );
  }

  List<Map<String, dynamic>> batchesPosted() {
    final calls = verify(
      () => dio.post<dynamic>(
        'analytics/events/batch',
        data: captureAny(named: 'data'),
      ),
    ).captured;
    return [
      for (final call in calls)
        for (final event in call as List) event as Map<String, dynamic>,
    ];
  }

  test('une impression est bufferisée, pas postée unitairement', () async {
    final service = AnalyticsService(api, posthog: posthog);

    await impress(service, contentId: 'a');

    expect(service.pendingEventCount, 1);
    verifyNever(
      () => dio.post<dynamic>('analytics/events', data: any(named: 'data')),
    );
    verifyNever(
      () =>
          dio.post<dynamic>('analytics/events/batch', data: any(named: 'data')),
    );
  });

  test('le buffer part en un seul POST batch au 25e event', () async {
    final service = AnalyticsService(api, posthog: posthog);

    for (var i = 0; i < 25; i++) {
      await impress(service, contentId: 'content-$i', position: i);
    }

    expect(service.pendingEventCount, 0);
    final posted = batchesPosted();
    expect(posted, hasLength(25));
    expect(
      posted.map((e) => e['event_type']).toSet(),
      {'article_impression'},
    );
  });

  test('flushPendingEvents vide un lot partiel', () async {
    final service = AnalyticsService(api, posthog: posthog);
    await impress(service, contentId: 'a');
    await impress(service, contentId: 'b');

    await service.flushPendingEvents();

    expect(service.pendingEventCount, 0);
    expect(batchesPosted(), hasLength(2));
  });

  test('flushPendingEvents sur buffer vide ne poste rien', () async {
    final service = AnalyticsService(api, posthog: posthog);

    await service.flushPendingEvents();

    verifyNever(
      () =>
          dio.post<dynamic>('analytics/events/batch', data: any(named: 'data')),
    );
  });

  test('dédup 1×/(contentId, sectionKey, jour)', () async {
    final service = AnalyticsService(api, posthog: posthog);

    await impress(service, contentId: 'a');
    await impress(service, contentId: 'a');
    await impress(service, contentId: 'a');
    await service.flushPendingEvents();

    expect(batchesPosted(), hasLength(1));
  });

  test('le même article dans deux sections compte deux impressions', () async {
    final service = AnalyticsService(api, posthog: posthog);

    await impress(service, contentId: 'a', sectionKey: 'theme:politique');
    await impress(service, contentId: 'a', sectionKey: 'source:lemonde');
    await service.flushPendingEvents();

    expect(batchesPosted(), hasLength(2));
  });

  test('la dédup survit à une relance dans la journée', () async {
    await AnalyticsService(api, posthog: posthog).trackArticleImpression(
      contentId: 'a',
      sectionKey: 'theme:politique',
      sectionFamily: 'theme',
      surface: 'tournee',
      dayKey: '2026-08-02',
      sectionIndex: 0,
      positionInSection: 0,
      globalPosition: 0,
    );

    // Nouveau process : le garde-fou mémoire est vide, seul SharedPreferences
    // se souvient.
    final afterRestart = AnalyticsService(api, posthog: posthog);
    await impress(afterRestart, contentId: 'a');
    await afterRestart.flushPendingEvents();

    expect(afterRestart.pendingEventCount, 0);
    verifyNever(
      () =>
          dio.post<dynamic>('analytics/events/batch', data: any(named: 'data')),
    );
  });

  test('le changement de jour purge la dédup de la veille', () async {
    final service = AnalyticsService(api, posthog: posthog);

    await impress(service, contentId: 'a', dayKey: '2026-08-01');
    await impress(service, contentId: 'a', dayKey: '2026-08-02');
    await service.flushPendingEvents();

    expect(batchesPosted(), hasLength(2));

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList('article_impressions_v1')!;
    expect(stored, ['2026-08-02|theme:politique|a']);
  });

  test('aucun miroir PostHog — la mesure est backend-only', () async {
    final service = AnalyticsService(api, posthog: posthog);

    await impress(service, contentId: 'a');
    await service.flushPendingEvents();

    expect(posthog.captured, isEmpty);
  });

  test('les propriétés de découpe de la jauge sont portées', () async {
    final service = AnalyticsService(api, posthog: posthog);

    await impress(service, contentId: 'a', position: 2, scoreTotal: 61.5);
    await service.flushPendingEvents();

    final data = batchesPosted().single['event_data'] as Map<String, dynamic>;
    expect(data['content_id'], 'a');
    expect(data['section_key'], 'theme:politique');
    expect(data['section_family'], 'theme');
    expect(data['surface'], 'tournee');
    expect(data['section_index'], 1);
    expect(data['position_in_section'], 2);
    expect(data['global_position'], 7);
    expect(data['score_total'], 61.5);
    expect(data['theme'], 'politique');
    expect(data['source_id'], 'source-1');
    expect(data['day_key'], '2026-08-02');
    // `algo_version` est estampillé côté serveur : le client ne le pose pas.
    expect(data.containsKey('algo_version'), isFalse);
  });

  test('un score absent passe en null sans faire échouer l\'event', () async {
    final service = AnalyticsService(api, posthog: posthog);

    await impress(service, contentId: 'a');
    await service.flushPendingEvents();

    final data = batchesPosted().single['event_data'] as Map<String, dynamic>;
    expect(data['score_total'], isNull);
    expect(data['block_score'], isNull);
  });

  test('endSession flush le buffer avant de poster session_end', () async {
    final service = AnalyticsService(api, posthog: posthog);
    await service.startSession();
    await impress(service, contentId: 'a');

    await service.endSession();

    expect(service.pendingEventCount, 0);
    expect(batchesPosted(), hasLength(1));
  });

  test('session_start porte la sonde tournee_customized', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'tournee_customized_v1': true,
    });
    final service = AnalyticsService(api, posthog: posthog);

    await service.startSession();

    final calls = verify(
      () => dio.post<dynamic>(
        'analytics/events',
        data: captureAny(named: 'data'),
      ),
    ).captured;
    final payload = calls.single as Map<String, dynamic>;
    expect(payload['event_data']['tournee_customized'], isTrue);
  });

  test('AnalyticsService.disabled ne bufferise rien', () async {
    final service = AnalyticsService.disabled();

    await impress(service, contentId: 'a');

    expect(service.pendingEventCount, 0);
  });
}
