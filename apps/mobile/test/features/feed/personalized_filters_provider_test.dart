import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:facteur/features/onboarding/providers/onboarding_provider.dart';
import 'package:facteur/features/feed/providers/personalized_filters_provider.dart';

void main() {
  setUpAll(() {
    Hive.init('.');
  });

  group('PersonalizedFiltersProvider', () {
    test('Default order when no specific preference', () {
      final container = ProviderContainer(
        overrides: [
          onboardingProvider.overrideWith((ref) => OnboardingNotifier()),
        ],
      );

      final filters = container.read(personalizedFiltersProvider);

      expect(filters.length, 3);
      expect(filters[0].key, 'inspiration');
      expect(filters[1].key, 'perspectives');
      expect(filters[2].key, 'deep_dive');
    });

    test('Prioritizes "deep_dive" when objective is "learn"', () {
      final container = ProviderContainer(
        overrides: [
          onboardingProvider.overrideWith((ref) {
            final notifier = OnboardingNotifier();
            // Manually set state via available public methods to avoid side effects of bypassOnboarding
            notifier.selectObjectives(['learn']);
            return notifier;
          }),
        ],
      );

      final filters = container.read(personalizedFiltersProvider);

      // Logic: objective='learn' -> deep_dive moved to front.
      expect(filters[0].key, 'deep_dive');
    });

    test('Prioritizes "inspiration" when objective includes "anxiety"', () {
      final container = ProviderContainer(
        overrides: [
          onboardingProvider.overrideWith((ref) {
            final notifier = OnboardingNotifier();
            // Posture/perspective ne sont plus collectés (v6) : « Rester serein »
            // est désormais priorisé via l'objectif « anxiety ». On combine avec
            // « learn » (qui pousse deep_dive en tête) pour vérifier que serein
            // repasse bien devant.
            notifier.selectObjectives(['learn', 'anxiety']);
            return notifier;
          }),
        ],
      );

      final filters = container.read(personalizedFiltersProvider);

      // learn → deep_dive en tête, puis anxiety → inspiration repasse devant.
      expect(filters[0].key, 'inspiration');
      expect(filters[1].key, 'deep_dive');
    });
  });
}
