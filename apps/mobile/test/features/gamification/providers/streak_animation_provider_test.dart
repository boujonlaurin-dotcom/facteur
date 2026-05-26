import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:facteur/features/gamification/providers/gamification_preference_provider.dart';
import 'package:facteur/features/gamification/providers/streak_animation_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('daily animation only triggers once per local date', () async {
    final container = ProviderContainer(
      overrides: [
        gamificationPreferenceProvider.overrideWith((ref) async => true),
        streakAnimationClockProvider.overrideWithValue(
          () => DateTime(2026, 5, 26, 9),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(await container.read(streakDailyAnimationProvider.future), isTrue);

    await container
        .read(streakDailyAnimationGateProvider)
        .markAnimatedForToday();
    container.invalidate(streakDailyAnimationProvider);

    expect(await container.read(streakDailyAnimationProvider.future), isFalse);

    final nextDayContainer = ProviderContainer(
      overrides: [
        gamificationPreferenceProvider.overrideWith((ref) async => true),
        streakAnimationClockProvider.overrideWithValue(
          () => DateTime(2026, 5, 27, 9),
        ),
      ],
    );
    addTearDown(nextDayContainer.dispose);

    expect(
      await nextDayContainer.read(streakDailyAnimationProvider.future),
      isTrue,
    );
  });
}
