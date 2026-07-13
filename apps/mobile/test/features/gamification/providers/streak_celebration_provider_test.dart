import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:facteur/features/gamification/providers/gamification_preference_provider.dart';
import 'package:facteur/features/gamification/providers/streak_animation_provider.dart';
import 'package:facteur/features/gamification/providers/streak_celebration_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('celebration only fires once per tournée-day (07h30 Paris boundary)',
      () async {
    // 09h00 Paris → jour-tournée courant (après la frontière 07h30).
    final container = ProviderContainer(
      overrides: [
        gamificationPreferenceProvider.overrideWith((ref) async => true),
        streakAnimationClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 5, 26, 7), // 09h Paris (UTC+2 été)
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(
      await container.read(streakCelebrationEligibleProvider.future),
      isTrue,
    );

    await container
        .read(streakCelebrationGateProvider)
        .markCelebratedForToday();
    container.invalidate(streakCelebrationEligibleProvider);

    expect(
      await container.read(streakCelebrationEligibleProvider.future),
      isFalse,
    );

    // Lendemain (même heure) → gate rouvert.
    final nextDay = ProviderContainer(
      overrides: [
        gamificationPreferenceProvider.overrideWith((ref) async => true),
        streakAnimationClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 5, 27, 7),
        ),
      ],
    );
    addTearDown(nextDay.dispose);

    expect(
      await nextDay.read(streakCelebrationEligibleProvider.future),
      isTrue,
    );
  });

  test('a marked date before the 07h30 boundary still belongs to prev day',
      () async {
    // 06h00 Paris (04h UTC) = encore le jour-tournée de la veille (25/05).
    final gate = StreakCelebrationGate(
      now: () => DateTime.utc(2026, 5, 26, 4),
    );
    await gate.markCelebratedForToday();

    // 09h00 Paris le 25/05 (07h UTC) = même jour-tournée → déjà célébré.
    final prevEvening = StreakCelebrationGate(
      now: () => DateTime.utc(2026, 5, 25, 7),
    );
    expect(await prevEvening.shouldCelebrateToday(), isFalse);
  });

  test('not eligible when gamification is disabled', () async {
    final container = ProviderContainer(
      overrides: [
        gamificationPreferenceProvider.overrideWith((ref) async => false),
        streakAnimationClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 5, 26, 7),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(
      await container.read(streakCelebrationEligibleProvider.future),
      isFalse,
    );
  });
}
