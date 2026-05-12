import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:facteur/core/nudges/nudge.dart';
import 'package:facteur/core/nudges/nudge_ids.dart';
import 'package:facteur/core/nudges/nudge_registry.dart';
import 'package:facteur/core/nudges/nudge_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('NudgeStorage — seen flag', () {
    test('isSeen defaults to false when no value set', () async {
      final storage = NudgeStorage(prefs: await SharedPreferences.getInstance());
      final nudge = NudgeRegistry.get(NudgeIds.widgetPinAndroid);
      expect(await storage.isSeen(nudge), isFalse);
    });

    test('markSeen + isSeen roundtrip via namespaced key', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = NudgeStorage(prefs: prefs);
      final nudge = NudgeRegistry.get(NudgeIds.widgetPinAndroid);

      await storage.markSeen(nudge);

      expect(await storage.isSeen(nudge), isTrue);
      expect(prefs.getBool('nudge.widget_pin_android.seen'), isTrue);
    });

    test('legacy key is read when namespaced key missing', () async {
      SharedPreferences.setMockInitialValues({
        'has_seen_widget_pin_nudge': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final storage = NudgeStorage(prefs: prefs);
      final nudge = NudgeRegistry.get(NudgeIds.widgetPinAndroid);

      expect(await storage.isSeen(nudge), isTrue);
    });

    test('legacy key is ALSO written for defensive rollback', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = NudgeStorage(prefs: prefs);
      final nudge = NudgeRegistry.get(NudgeIds.widgetPinAndroid);

      await storage.markSeen(nudge);

      expect(prefs.getBool('has_seen_widget_pin_nudge'), isTrue);
    });

    test('namespaced value takes precedence over legacy', () async {
      SharedPreferences.setMockInitialValues({
        'has_seen_widget_pin_nudge': true,
        'nudge.widget_pin_android.seen': false,
      });
      final prefs = await SharedPreferences.getInstance();
      final storage = NudgeStorage(prefs: prefs);
      final nudge = NudgeRegistry.get(NudgeIds.widgetPinAndroid);

      expect(await storage.isSeen(nudge), isFalse);
    });
  });

  group('NudgeStorage — cooldown timestamps', () {
    test('legacy ISO8601 string is parsed for lastShown', () async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      SharedPreferences.setMockInitialValues({
        'sunflower_last_nudge_date': yesterday.toIso8601String(),
      });
      final prefs = await SharedPreferences.getInstance();
      final storage = NudgeStorage(prefs: prefs);
      final nudge = NudgeRegistry.get(NudgeIds.sunflowerRecommend);

      final last = await storage.lastShown(nudge);
      expect(last, isNotNull);
      expect(last!.difference(yesterday).inSeconds.abs(), lessThan(2));
    });

    test('legacy int epoch is parsed for lastShown', () async {
      final ts = DateTime.now().subtract(const Duration(hours: 5));
      SharedPreferences.setMockInitialValues({
        'saved_nudge_dismissed_at': ts.millisecondsSinceEpoch,
      });
      final prefs = await SharedPreferences.getInstance();
      final storage = NudgeStorage(prefs: prefs);
      final nudge = NudgeRegistry.get(NudgeIds.savedUnread);

      final last = await storage.lastShown(nudge);
      expect(last, isNotNull);
      expect(last!.millisecondsSinceEpoch, ts.millisecondsSinceEpoch);
    });

    test('recordShown writes namespaced + legacy keys', () async {
      final prefs = await SharedPreferences.getInstance();
      final storage = NudgeStorage(prefs: prefs);
      final nudge = NudgeRegistry.get(NudgeIds.sunflowerRecommend);
      final when = DateTime(2026, 4, 23, 10, 0);

      await storage.recordShown(nudge, at: when);

      expect(prefs.getInt('nudge.sunflower_recommend.lastShown'),
          when.millisecondsSinceEpoch);
      expect(prefs.getInt('sunflower_last_nudge_date'),
          when.millisecondsSinceEpoch);
    });
  });

  test('Nudge const validation — cooldown requires a duration', () {
    expect(
      () => Nudge(
        id: 'broken',
        surface: NudgeSurface.global,
        placement: NudgePlacement.overlay,
        priority: NudgePriority.low,
        frequency: NudgeFrequency.cooldown,
      ),
      throwsA(isA<AssertionError>()),
    );
  });
}
