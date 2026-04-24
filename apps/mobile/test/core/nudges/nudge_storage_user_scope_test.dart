import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:facteur/core/nudges/nudge.dart';
import 'package:facteur/core/nudges/nudge_ids.dart';
import 'package:facteur/core/nudges/nudge_registry.dart';
import 'package:facteur/core/nudges/nudge_storage.dart';

/// Regression tests for the device-scoped vs user-scoped "seen" state.
///
/// Bug 1 fix: a second account on the same device must see the Welcome Tour
/// even if another account already marked it seen via the device-scoped key.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NudgeStorage storage;
  late Nudge welcomeTour;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    storage = NudgeStorage(prefs: prefs);
    welcomeTour = NudgeRegistry.get(NudgeIds.welcomeTour);
  });

  test('isSeenForUser returns false on empty store', () async {
    expect(await storage.isSeenForUser(welcomeTour, 'userA'), isFalse);
  });

  test(
    'markSeenForUser marks only the targeted user (second user still sees tour)',
    () async {
      await storage.markSeenForUser(welcomeTour, 'userA');
      expect(await storage.isSeenForUser(welcomeTour, 'userA'), isTrue);
      expect(await storage.isSeenForUser(welcomeTour, 'userB'), isFalse);
    },
  );

  test(
    'legacy device-scoped "seen" is NOT honored for a new user (bug 1 fix)',
    () async {
      // Simulate a user who saw the tour in v1 (device-scoped key set)
      SharedPreferences.setMockInitialValues({
        'nudge.welcome_tour.seen': true,
      });
      final prefs = await SharedPreferences.getInstance();
      storage = NudgeStorage(prefs: prefs);

      // A fresh user on the same device should still see the tour
      expect(await storage.isSeenForUser(welcomeTour, 'newUser'), isFalse);
    },
  );

  test('markSeenForUser also writes device-scoped key for legacy callers',
      () async {
    await storage.markSeenForUser(welcomeTour, 'userA');
    expect(await storage.isSeen(welcomeTour), isTrue);
  });
}
