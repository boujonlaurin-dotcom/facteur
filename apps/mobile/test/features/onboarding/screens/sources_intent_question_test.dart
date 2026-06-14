import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/core/providers/analytics_provider.dart';
import 'package:facteur/core/services/analytics_service.dart';
import 'package:facteur/features/onboarding/onboarding_strings.dart';
import 'package:facteur/features/onboarding/providers/onboarding_provider.dart';
import 'package:facteur/features/onboarding/screens/questions/sources_intent_question.dart';

void main() {
  // Hive est initialisé mais la box n'est jamais ouverte hors zone de test :
  // les openBox/put de l'OnboardingNotifier (lancés dans la zone fake-async
  // de testWidgets) restent en attente sans bloquer les tests suivants, et
  // chaque test repart d'un état vierge.
  setUpAll(() {
    Hive.init(Directory.systemTemp.createTempSync('onb_intent_test').path);
  });

  Widget buildTestWidget(ProviderContainer container) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: FacteurTheme.lightTheme,
        home: const Scaffold(body: SourcesIntentQuestion()),
      ),
    );
  }

  ProviderContainer makeContainer() {
    final container = ProviderContainer(overrides: [
      analyticsServiceProvider.overrideWithValue(AnalyticsService.disabled()),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  testWidgets('affiche le titre et les deux cartes', (tester) async {
    final container = makeContainer();
    await tester.pumpWidget(buildTestWidget(container));

    expect(find.text(OnboardingStrings.sourcesIntentTitle), findsOneWidget);
    expect(
      find.text(OnboardingStrings.sourcesIntentCuriousLabel),
      findsOneWidget,
    );
    expect(
      find.text(OnboardingStrings.sourcesIntentCuriousSubtitle),
      findsOneWidget,
    );
    expect(
      find.text(OnboardingStrings.sourcesIntentKnowsLabel),
      findsOneWidget,
    );
    expect(
      find.text(OnboardingStrings.sourcesIntentKnowsSubtitle),
      findsOneWidget,
    );

  });

  testWidgets('tap « Plutôt curieux » : intent enregistré + route vers le swipe',
      (tester) async {
    final container = makeContainer();
    await tester.pumpWidget(buildTestWidget(container));

    await tester.tap(find.text(OnboardingStrings.sourcesIntentCuriousLabel));
    await tester.pump();

    expect(container.read(onboardingProvider).answers.sourcesIntent, 'curious');

    await tester.pump(const Duration(milliseconds: 350));
    // Parcours curieux → étape swipe désambiguateur (v6) avant la page sources.
    expect(
      container.read(onboardingProvider).currentQuestionIndex,
      Section3Question.swipe.index,
    );

  });

  testWidgets('tap « Repartir de ce que je connais » : intent knows',
      (tester) async {
    final container = makeContainer();
    await tester.pumpWidget(buildTestWidget(container));

    await tester.tap(find.text(OnboardingStrings.sourcesIntentKnowsLabel));
    await tester.pump();

    expect(container.read(onboardingProvider).answers.sourcesIntent, 'knows');

    await tester.pump(const Duration(milliseconds: 350));
    expect(
      container.read(onboardingProvider).currentQuestionIndex,
      Section3Question.sources.index,
    );

  });
}
