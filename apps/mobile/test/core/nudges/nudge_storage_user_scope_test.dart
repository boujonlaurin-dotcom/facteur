import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:facteur/core/nudges/nudge.dart';
import 'package:facteur/core/nudges/nudge_ids.dart';
import 'package:facteur/core/nudges/nudge_registry.dart';
import 'package:facteur/core/nudges/nudge_storage.dart';

/// Regression tests for the device-scoped vs user-scoped "seen" state.
///
/// Bug 1 fix: a second account on the same device must see a "once" nudge
/// even if another account already marked it seen via the device-scoped key.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NudgeStorage storage;
  late Nudge widgetPin;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    storage = NudgeStorage(prefs: prefs);
    widgetPin = NudgeRegistry.get(NudgeIds.widgetPinAndroid);
  });

  test('isSeenForUser returns false on empty store', () async {
    expect(await storage.isSeenForUser(widgetPin, 'userA'), isFalse);
  });

  test(
    'markSeenForUser marks only the targeted user (second user still sees nudge)',
    () async {
      await storage.markSeenForUser(widgetPin, 'userA');
      expect(await storage.isSeenForUser(widgetPin, 'userA'), isTrue);
      expect(await storage.isSeenForUser(widgetPin, 'userB'), isFalse);
    },
  );

  test(
    'legacy device-scoped "seen" is NOT honored for a new user (bug 1 fix)',
    () async {
      // Simulate a user who already saw the nudge (device-scoped key set)
      SharedPreferences.setMockInitialValues({
        'nudge.widget_pin_android.seen': true,
      });
      final prefs = await SharedPreferences.getInstance();
      storage = NudgeStorage(prefs: prefs);

      // A fresh user on the same device should still see the nudge
      expect(await storage.isSeenForUser(widgetPin, 'newUser'), isFalse);
    },
  );

  test('markSeenForUser also writes device-scoped key for legacy callers',
      () async {
    await storage.markSeenForUser(widgetPin, 'userA');
    expect(await storage.isSeen(widgetPin), isTrue);
  });
}
