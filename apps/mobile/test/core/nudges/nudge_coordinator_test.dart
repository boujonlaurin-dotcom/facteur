import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:facteur/core/nudges/nudge_coordinator.dart';
import 'package:facteur/core/nudges/nudge_ids.dart';
import 'package:facteur/core/nudges/nudge_service.dart';
import 'package:facteur/core/nudges/nudge_storage.dart';

NudgeCoordinator _makeCoordinator({DateTime Function()? clock}) {
  final storage = NudgeStorage();
  final service = NudgeService(storage: storage, clock: clock);
  return NudgeCoordinator(service: service, clock: clock);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('NudgeCoordinator — single request', () {
    test('first request becomes active', () async {
      final c = _makeCoordinator();
      final active = await c.request(NudgeIds.digestWelcome);
      expect(active, NudgeIds.digestWelcome);
      expect(c.activeId, NudgeIds.digestWelcome);
    });

    test('already-seen nudge is not activated', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('nudge.digest_welcome.seen', true);
      final c = _makeCoordinator();
      final active = await c.request(NudgeIds.digestWelcome);
      expect(active, isNull);
    });

    test('dismiss advances to next queued nudge', () async {
      final c = _makeCoordinator();
      await c.request(NudgeIds.digestWelcome);
      await c.request(NudgeIds.widgetPinAndroid);
      expect(c.activeId, NudgeIds.digestWelcome);
      await c.dismiss(markSeen: true);
      expect(c.activeId, NudgeIds.widgetPinAndroid);
    });
  });

  group('NudgeCoordinator — priority & queue', () {
    test('higher priority nudge preempts active lower-priority one', () async {
      final c = _makeCoordinator();
      await c.request(NudgeIds.noteWelcome); // normal
      expect(c.activeId, NudgeIds.noteWelcome);
      await c.request(NudgeIds.digestWelcome); // high
      expect(c.activeId, NudgeIds.digestWelcome);
      // noteWelcome should have been pushed back to the queue.
      expect(c.queuedIds, contains(NudgeIds.noteWelcome));
    });

    test('lower priority request queues behind active', () async {
      final c = _makeCoordinator();
      await c.request(NudgeIds.digestWelcome); // high
      await c.request(NudgeIds.noteWelcome); // normal
      expect(c.activeId, NudgeIds.digestWelcome);
      expect(c.queuedIds.first, NudgeIds.noteWelcome);
    });

    test('queue is sorted by priority after additions', () async {
      final c = _makeCoordinator();
      await c.request(NudgeIds.widgetPinAndroid); // high -> active
      await c.request(NudgeIds.articleReadOnSite); // low
      await c.request(NudgeIds.noteWelcome); // normal
      // Queue should be: [normal, low] (normal is higher than low).
      expect(c.queuedIds, [
        NudgeIds.noteWelcome,
        NudgeIds.articleReadOnSite,
      ]);
    });
  });

  group('NudgeCoordinator — prerequisites', () {
    test('nudge with unmet prerequisite is rejected', () async {
      final c = _makeCoordinator();
      // feedBadgeLongpress requires welcomeTour to be seen.
      final active = await c.request(NudgeIds.feedBadgeLongpress);
      expect(active, isNull);
    });

    test('nudge becomes eligible once prerequisite marked seen', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('nudge.welcome_tour.seen', true);
      final c = _makeCoordinator();
      final active = await c.request(NudgeIds.feedBadgeLongpress);
      expect(active, NudgeIds.feedBadgeLongpress);
    });
  });

  group('NudgeCoordinator — session budget & global cooldown', () {
    test('critical / high nudges do NOT consume the session budget',
        () async {
      final c = _makeCoordinator();
      await c.request(NudgeIds.digestWelcome); // high
      await c.dismiss(markSeen: true);
      await c.request(NudgeIds.widgetPinAndroid); // high
      await c.dismiss(markSeen: true);
      // Normal nudge must still be eligible afterwards.
      final active = await c.request(NudgeIds.noteWelcome); // normal
      expect(active, NudgeIds.noteWelcome);
    });

    test('second non-critical nudge blocked by session budget', () async {
      final c = _makeCoordinator();
      await c.request(NudgeIds.noteWelcome); // normal
      await c.dismiss(markSeen: true);
      final active = await c.request(NudgeIds.prioritySliderExplainer);
      expect(active, isNull);
    });

    test('24h cooldown blocks a 2nd non-critical within the same session',
        () async {
      final c = _makeCoordinator();
      await c.request(NudgeIds.noteWelcome); // normal, consumes budget + cooldown
      await c.dismiss(markSeen: true);
      final blocked = await c.request(NudgeIds.prioritySliderExplainer);
      expect(blocked, isNull);
    });

    test('a fresh session has no in-memory cooldown (persistence is per-id)',
        () async {
      final c1 = _makeCoordinator();
      await c1.request(NudgeIds.noteWelcome);
      await c1.dismiss(markSeen: true);
      // A new coordinator has a clean in-memory budget and cooldown.
      // prioritySliderExplainer has its own per-id state (never shown).
      final c2 = _makeCoordinator();
      final active = await c2.request(NudgeIds.prioritySliderExplainer);
      expect(active, NudgeIds.prioritySliderExplainer);
    });
  });

  group('NudgeCoordinator — frequency', () {
    test('once-frequency nudge marked seen on dismiss(markSeen=true)',
        () async {
      final c = _makeCoordinator();
      await c.request(NudgeIds.digestWelcome);
      await c.dismiss(markSeen: true);
      final again = await c.request(NudgeIds.digestWelcome);
      expect(again, isNull);
    });

    test('dismiss(markSeen=false) allows nudge to show again', () async {
      final c = _makeCoordinator();
      await c.request(NudgeIds.digestWelcome);
      await c.dismiss(markSeen: false);
      c.resetSession();
      final again = await c.request(NudgeIds.digestWelcome);
      expect(again, NudgeIds.digestWelcome);
    });

    test('cooldown-frequency nudge re-eligible after cooldown elapses',
        () async {
      final base = DateTime(2026, 4, 23, 10, 0);
      var now = base;
      final c = _makeCoordinator(clock: () => now);
      await c.request(NudgeIds.sunflowerRecommend);
      await c.dismiss(markSeen: false);
      // 2 days later -> still inside 3-day cooldown.
      now = base.add(const Duration(days: 2));
      final blocked = await c.request(NudgeIds.sunflowerRecommend);
      expect(blocked, isNull);
      // 4 days later -> cooldown elapsed.
      now = base.add(const Duration(days: 4));
      c.resetSession();
      final reopened = await c.request(NudgeIds.sunflowerRecommend);
      expect(reopened, NudgeIds.sunflowerRecommend);
    });
  });
}
