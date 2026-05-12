import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:facteur/core/nudges/nudge_coordinator.dart';
import 'package:facteur/core/nudges/nudge_ids.dart';
import 'package:facteur/core/nudges/nudge_service.dart';
import 'package:facteur/core/nudges/nudge_storage.dart';

NudgeCoordinator _makeCoordinator({
  DateTime Function()? clock,
  Future<bool> Function()? isEnabled,
}) {
  final storage = NudgeStorage();
  final service = NudgeService(storage: storage, clock: clock);
  return NudgeCoordinator(
    service: service,
    clock: clock,
    isEnabled: isEnabled,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('NudgeCoordinator — single request', () {
    test('first request becomes active', () async {
      final c = _makeCoordinator();
      final active = await c.request(NudgeIds.widgetPinAndroid);
      expect(active, NudgeIds.widgetPinAndroid);
      expect(c.activeId, NudgeIds.widgetPinAndroid);
    });

    test('already-seen nudge is not activated', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('nudge.widget_pin_android.seen', true);
      final c = _makeCoordinator();
      final active = await c.request(NudgeIds.widgetPinAndroid);
      expect(active, isNull);
    });

    test('dismiss advances to next queued nudge', () async {
      final c = _makeCoordinator();
      await c.request(NudgeIds.widgetPinAndroid);
      await c.request(NudgeIds.feedBadgeLongpress);
      expect(c.activeId, NudgeIds.widgetPinAndroid);
      await c.dismiss(markSeen: true);
      expect(c.activeId, NudgeIds.feedBadgeLongpress);
    });
  });

  group('NudgeCoordinator — priority & queue', () {
    test('higher priority nudge preempts active lower-priority one', () async {
      final c = _makeCoordinator();
      await c.request(NudgeIds.articleSaveNotes); // normal
      expect(c.activeId, NudgeIds.articleSaveNotes);
      await c.request(NudgeIds.widgetPinAndroid); // high
      expect(c.activeId, NudgeIds.widgetPinAndroid);
      // articleSaveNotes should have been pushed back to the queue.
      expect(c.queuedIds, contains(NudgeIds.articleSaveNotes));
    });

    test('lower priority request queues behind active', () async {
      final c = _makeCoordinator();
      await c.request(NudgeIds.widgetPinAndroid); // high
      await c.request(NudgeIds.articleSaveNotes); // normal
      expect(c.activeId, NudgeIds.widgetPinAndroid);
      expect(c.queuedIds.first, NudgeIds.articleSaveNotes);
    });

    test('queue is sorted by priority after additions', () async {
      final c = _makeCoordinator();
      await c.request(NudgeIds.widgetPinAndroid); // high -> active
      await c.request(NudgeIds.articleReadOnSite); // low
      await c.request(NudgeIds.articleSaveNotes); // normal
      // Queue should be: [normal, low] (normal is higher than low).
      expect(c.queuedIds, [
        NudgeIds.articleSaveNotes,
        NudgeIds.articleReadOnSite,
      ]);
    });
  });

  group('NudgeCoordinator — prerequisites', () {
    test('nudge with unmet prerequisite is rejected', () async {
      final c = _makeCoordinator();
      // feedPreviewLongpress requires feedBadgeLongpress to be seen.
      final active = await c.request(NudgeIds.feedPreviewLongpress);
      expect(active, isNull);
    });

    test('nudge becomes eligible once prerequisite marked seen', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('nudge.feed_badge_longpress.seen', true);
      final c = _makeCoordinator();
      final active = await c.request(NudgeIds.feedPreviewLongpress);
      expect(active, NudgeIds.feedPreviewLongpress);
    });
  });

  group('NudgeCoordinator — session budget & global cooldown', () {
    test('high priority nudges do NOT consume the session budget', () async {
      final c = _makeCoordinator();
      await c.request(NudgeIds.widgetPinAndroid); // high
      await c.dismiss(markSeen: true);
      await c.request(NudgeIds.feedBadgeLongpress); // high
      await c.dismiss(markSeen: true);
      // Normal nudge must still be eligible afterwards.
      final active = await c.request(NudgeIds.articleSaveNotes); // normal
      expect(active, NudgeIds.articleSaveNotes);
    });

    test('second non-critical nudge blocked by session budget', () async {
      final c = _makeCoordinator();
      await c.request(NudgeIds.articleSaveNotes); // normal
      await c.dismiss(markSeen: true);
      final active = await c.request(NudgeIds.prioritySliderExplainer);
      expect(active, isNull);
    });

    test('24h cooldown blocks a 2nd non-critical within the same session',
        () async {
      final c = _makeCoordinator();
      await c.request(NudgeIds.articleSaveNotes); // normal, consumes budget + cooldown
      await c.dismiss(markSeen: true);
      final blocked = await c.request(NudgeIds.prioritySliderExplainer);
      expect(blocked, isNull);
    });

    test('a fresh session has no in-memory cooldown (persistence is per-id)',
        () async {
      final c1 = _makeCoordinator();
      await c1.request(NudgeIds.articleSaveNotes);
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
      await c.request(NudgeIds.widgetPinAndroid);
      await c.dismiss(markSeen: true);
      final again = await c.request(NudgeIds.widgetPinAndroid);
      expect(again, isNull);
    });

    test('dismiss(markSeen=false) allows nudge to show again', () async {
      final c = _makeCoordinator();
      await c.request(NudgeIds.widgetPinAndroid);
      await c.dismiss(markSeen: false);
      c.resetSession();
      final again = await c.request(NudgeIds.widgetPinAndroid);
      expect(again, NudgeIds.widgetPinAndroid);
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

  group('NudgeCoordinator — kill switch', () {
    test('disabled: non-critical nudges are rejected', () async {
      final c = _makeCoordinator(isEnabled: () async => false);
      final active = await c.request(NudgeIds.widgetPinAndroid); // high
      expect(active, isNull);
    });

    test('enabled flag flip allows a previously rejected nudge', () async {
      var enabled = false;
      final c = _makeCoordinator(isEnabled: () async => enabled);
      expect(await c.request(NudgeIds.widgetPinAndroid), isNull);
      enabled = true;
      expect(await c.request(NudgeIds.widgetPinAndroid),
          NudgeIds.widgetPinAndroid);
    });
  });

  group('NudgeCoordinator — markConverted', () {
    test('markConverted dismisses + marks seen + does not re-show', () async {
      final c = _makeCoordinator();
      await c.request(NudgeIds.widgetPinAndroid);
      final result = await c.markConverted(NudgeIds.widgetPinAndroid);
      expect(result, isNull);
      final again = await c.request(NudgeIds.widgetPinAndroid);
      expect(again, isNull);
    });

    test('markConverted is a no-op when id does not match active', () async {
      final c = _makeCoordinator();
      await c.request(NudgeIds.widgetPinAndroid);
      final result = await c.markConverted(NudgeIds.articleSaveNotes);
      expect(result, NudgeIds.widgetPinAndroid);
      expect(c.activeId, NudgeIds.widgetPinAndroid);
    });
  });
}
