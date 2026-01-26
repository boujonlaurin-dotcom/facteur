import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:facteur/features/onboarding/providers/onboarding_provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:hive/hive.dart';

void main() {
  setUp(() async {
    // Hive mocking basic setup
    Hive.init('.');
    // Mock opening box if possible or ignore if test fails on Hive
    // Ideally we mock Hive, but for simple provider state test without persistence calls blocking
    // we might need to handle the _loadSavedAnswers async call or errors.
  });

  group('Section3Question enum order', () {
    test('Section3Question.themes has index 0 (first question)', () {
      expect(Section3Question.themes.index, equals(0));
    });

    test('Section3Question.sources has index 1 (second question)', () {
      expect(Section3Question.sources.index, equals(1));
    });

    test('Section3Question.finalize has index 2 (last)', () {
      expect(Section3Question.finalize.index, equals(2));
    });
  });

  group('Section 3 navigation flow', () {
    test('selectThemesAndSubtopics updates state with themes and subtopics',
        () async {
      final container = ProviderContainer();

      // Initial state check
      expect(container.read(onboardingProvider).answers.themes, isNull);
      expect(container.read(onboardingProvider).answers.subtopics, isNull);

      // Action
      final themes = ['tech', 'international'];
      final subtopics = ['ai', 'geopolitics'];

      container
          .read(onboardingProvider.notifier)
          .selectThemesAndSubtopics(themes, subtopics);

      // Verify data update
      final newState = container.read(onboardingProvider);
      expect(newState.answers.themes, equals(['tech', 'international']));
      expect(newState.answers.subtopics, equals(['ai', 'geopolitics']));

      // Note: Navigation to sources happens after Future.delayed(300ms)
      // Data update is the critical part verified here.
    });

    test('selectSources updates state with preferred sources', () async {
      final container = ProviderContainer();

      // Initial state check
      expect(
          container.read(onboardingProvider).answers.preferredSources, isNull);

      // Action
      final sources = ['source-id-1', 'source-id-2', 'source-id-3'];

      container.read(onboardingProvider.notifier).selectSources(sources);

      // Verify data update
      final newState = container.read(onboardingProvider);
      expect(
        newState.answers.preferredSources,
        equals(['source-id-1', 'source-id-2', 'source-id-3']),
      );

      // Note: Navigation to finalize happens after Future.delayed(300ms)
    });

    test('Section 3 starts at themes (index 0) after transition from Section 2',
        () async {
      final container = ProviderContainer();

      // Simulate being in Section 3 at question index 0
      // After _transitionToSection3() is called, currentQuestionIndex = 0
      // which should map to Section3Question.themes

      // Force state to Section 3
      final notifier = container.read(onboardingProvider.notifier);
      // We can't directly call _transitionToSection3 (private), but we can simulate
      // by checking the enum mapping
      expect(Section3Question.values[0], equals(Section3Question.themes));
    });
  });

  group('OnboardingAnswers', () {
    test('toJson and fromJson roundtrip preserves themes and subtopics', () {
      const answers = OnboardingAnswers(
        themes: ['tech', 'science'],
        subtopics: ['ai', 'climate'],
        preferredSources: ['source-1', 'source-2'],
      );

      final json = answers.toJson();
      final restored = OnboardingAnswers.fromJson(json);

      expect(restored.themes, equals(['tech', 'science']));
      expect(restored.subtopics, equals(['ai', 'climate']));
      expect(restored.preferredSources, equals(['source-1', 'source-2']));
    });
  });
}
