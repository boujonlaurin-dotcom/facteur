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

  test('selectThemesAndSubtopics updates state correctly with subtopics',
      () async {
    // Setup Container
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

    // Verify
    final newState = container.read(onboardingProvider);
    expect(newState.answers.themes, equals(['tech', 'international']));
    expect(newState.answers.subtopics, equals(['ai', 'geopolitics']));

    // It should also transition to finalize (delayed)
    // We can't easily wait for Future.delayed in simple unit test without async elapsing
    // But verify the data update is the critical part here.
  });
}
