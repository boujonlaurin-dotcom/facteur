import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/core/nudges/nudge_coordinator.dart';
import 'package:facteur/core/nudges/nudge_events.dart';
import 'package:facteur/core/nudges/nudge_ids.dart';
import 'package:facteur/core/nudges/nudge_service.dart';
import 'package:facteur/core/nudges/nudge_storage.dart';
import 'package:facteur/core/services/posthog_service.dart';

import 'package:shared_preferences/shared_preferences.dart';

class _RecordingPostHog extends PostHogService {
  final List<({String event, Map<String, Object>? props})> calls = [];

  @override
  bool get isEnabled => true;

  @override
  Future<void> capture({
    required String event,
    Map<String, Object>? properties,
  }) async {
    calls.add((event: event, props: properties));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('request → dismiss emits shown + dismissed with outcome', () async {
    final recorder = _RecordingPostHog();
    final events = NudgeEvents(recorder);
    final coordinator = NudgeCoordinator(
      service: NudgeService(storage: NudgeStorage()),
      events: events,
    );

    await coordinator.request(NudgeIds.digestWelcome);
    await coordinator.dismiss(markSeen: true);

    expect(recorder.calls.length, 2);
    expect(recorder.calls[0].event, 'nudge_shown');
    expect(recorder.calls[0].props?['nudge_id'], NudgeIds.digestWelcome);
    expect(recorder.calls[0].props?['surface'], 'digest');
    expect(recorder.calls[1].event, 'nudge_dismissed');
    expect(recorder.calls[1].props?['outcome'], 'dismissed');
  });

  test('markConverted emits dismissed with outcome=converted', () async {
    final recorder = _RecordingPostHog();
    final events = NudgeEvents(recorder);
    final coordinator = NudgeCoordinator(
      service: NudgeService(storage: NudgeStorage()),
      events: events,
    );

    await coordinator.request(NudgeIds.digestWelcome);
    await coordinator.markConverted(NudgeIds.digestWelcome);

    expect(recorder.calls.length, 2);
    expect(recorder.calls[1].event, 'nudge_dismissed');
    expect(recorder.calls[1].props?['outcome'], 'converted');
  });

  test('preemption emits shown for the newly active nudge', () async {
    final recorder = _RecordingPostHog();
    final events = NudgeEvents(recorder);
    final coordinator = NudgeCoordinator(
      service: NudgeService(storage: NudgeStorage()),
      events: events,
    );

    // normal priority first
    await coordinator.request(NudgeIds.articleSaveNotes);
    // high priority preempts
    await coordinator.request(NudgeIds.digestWelcome);

    expect(recorder.calls.length, 2);
    expect(recorder.calls[0].props?['nudge_id'], NudgeIds.articleSaveNotes);
    expect(recorder.calls[1].props?['nudge_id'], NudgeIds.digestWelcome);
  });

  test('no events emitted when request is rejected', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('nudge.digest_welcome.seen', true);

    final recorder = _RecordingPostHog();
    final events = NudgeEvents(recorder);
    final coordinator = NudgeCoordinator(
      service: NudgeService(storage: NudgeStorage()),
      events: events,
    );

    await coordinator.request(NudgeIds.digestWelcome);
    expect(recorder.calls, isEmpty);
  });
}
