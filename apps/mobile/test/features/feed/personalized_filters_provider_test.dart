import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:facteur/features/onboarding/providers/onboarding_provider.dart';
import 'package:facteur/features/feed/providers/personalized_filters_provider.dart';

void main() {
  group('PersonalizedFiltersProvider', () {
    test('Default order when no specific preference', () {
      final container = ProviderContainer(
        overrides: [
          onboardingProvider.overrideWith((ref) => OnboardingNotifier()),
        ],
      );

      final filters = container.read(personalizedFiltersProvider);

      expect(filters.length, 4);
      expect(filters[0].key, 'breaking');
      expect(filters[1].key, 'inspiration');
      expect(filters[2].key, 'perspectives');
      expect(filters[3].key, 'deep_dive');
    });

    test('Prioritizes "deep_dive" when objective is "learn"', () {
      final container = ProviderContainer(
        overrides: [
          onboardingProvider.overrideWith((ref) {
            final notifier = OnboardingNotifier();
            // Manually set state via available public methods to avoid side effects of bypassOnboarding
            notifier.selectObjective('learn');
            return notifier;
          }),
        ],
      );

      final filters = container.read(personalizedFiltersProvider);

      // Logic: objective='learn' -> deep_dive moved to front.
      expect(filters[0].key, 'deep_dive');
    });

    test('Prioritizes "breaking" when response style is "decisive"', () {
      final container = ProviderContainer(
        overrides: [
          onboardingProvider.overrideWith((ref) {
            final notifier = OnboardingNotifier();
            notifier.selectResponseStyle('decisive');
            return notifier;
          }),
        ],
      );

      final filters = container.read(personalizedFiltersProvider);

      // Logic: decisive -> breaking moved to front.
      expect(filters[0].key, 'breaking');
    });

    test('Prioritizes "inspiration" when perspective is "big_picture"', () {
      final container = ProviderContainer(
        overrides: [
          onboardingProvider.overrideWith((ref) {
            final notifier = OnboardingNotifier();
            notifier.selectPerspective('big_picture');
            return notifier;
          }),
        ],
      );

      final filters = container.read(personalizedFiltersProvider);

      // Logic: big_picture -> inspiration moved to front.
      expect(filters[0].key, 'inspiration');
    });
  });
}
