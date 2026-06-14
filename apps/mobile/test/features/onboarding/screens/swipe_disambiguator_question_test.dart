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
import 'package:facteur/features/onboarding/screens/questions/swipe_disambiguator_question.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/features/sources/providers/sources_providers.dart';

class _FakeUserSourcesNotifier extends UserSourcesNotifier {
  _FakeUserSourcesNotifier(this._sources);
  final List<Source> _sources;

  @override
  Future<List<Source>> build() async => _sources;
}

/// Source curée minimale (logoUrl null → pas d'appel réseau dans les tests).
Source _src(
  String id, {
  String tier = 'mainstream',
  double? independence,
  String bias = 'unknown',
}) {
  return Source(
    id: id,
    name: 'Source $id',
    type: SourceType.article,
    theme: 'tech',
    isCurated: true,
    reliabilityScore: 'high',
    sourceTier: tier,
    scoreIndependence: independence,
    biasStance: bias,
  );
}

void main() {
  setUpAll(() {
    Hive.init(Directory.systemTemp.createTempSync('onb_swipe_test').path);
  });

  ProviderContainer makeContainer(List<Source> sources) {
    final container = ProviderContainer(overrides: [
      userSourcesProvider.overrideWith(() => _FakeUserSourcesNotifier(sources)),
      analyticsServiceProvider.overrideWithValue(AnalyticsService.disabled()),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  Widget buildTestWidget(ProviderContainer container) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: FacteurTheme.lightTheme,
        home: const Scaffold(body: SwipeDisambiguatorQuestion()),
      ),
    );
  }

  testWidgets('rend le titre et une carte source', (tester) async {
    final container = makeContainer([
      _src('main', tier: 'mainstream'),
      _src('deep', tier: 'deep'),
      _src('indie', independence: 0.9, bias: 'alternative'),
    ]);
    await tester.pumpWidget(buildTestWidget(container));
    await tester.pumpAndSettle();

    expect(find.text(OnboardingStrings.swipeTitle), findsOneWidget);
    // Au moins une carte du spanning set est rendue.
    expect(find.byType(Dismissible), findsOneWidget);
  });

  testWidgets('like (carte unique) enregistre le vote et avance vers sources',
      (tester) async {
    final container = makeContainer([_src('solo', tier: 'mainstream')]);
    await tester.pumpWidget(buildTestWidget(container));
    await tester.pumpAndSettle();

    await tester
        .tap(find.widgetWithIcon(InkWell, Icons.favorite_rounded));
    await tester.pump();

    expect(container.read(onboardingProvider).answers.swipeLiked,
        equals(['solo']));

    await tester.pump(const Duration(milliseconds: 350));
    expect(
      container.read(onboardingProvider).currentQuestionIndex,
      Section3Question.sources.index,
    );
  });

  testWidgets('skip (carte unique) enregistre le rejet et avance vers sources',
      (tester) async {
    final container = makeContainer([_src('solo', tier: 'mainstream')]);
    await tester.pumpWidget(buildTestWidget(container));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithIcon(InkWell, Icons.close_rounded));
    await tester.pump();

    expect(container.read(onboardingProvider).answers.swipeDisliked,
        equals(['solo']));
    expect(container.read(onboardingProvider).answers.swipeLiked, isEmpty);

    await tester.pump(const Duration(milliseconds: 350));
    expect(
      container.read(onboardingProvider).currentQuestionIndex,
      Section3Question.sources.index,
    );
  });

  testWidgets('spanning set vide : saute directement vers sources',
      (tester) async {
    final container = makeContainer(const []);
    await tester.pumpWidget(buildTestWidget(container));
    await tester.pump(); // résout le FutureProvider → _ensureBuilt → post-frame _complete()
    await tester.pump(const Duration(milliseconds: 350)); // transition completeSwipe

    expect(
      container.read(onboardingProvider).currentQuestionIndex,
      Section3Question.sources.index,
    );
  });
}
