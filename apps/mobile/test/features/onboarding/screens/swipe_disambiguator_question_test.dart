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

  testWidgets('rend le titre et les boutons d\'action', (tester) async {
    final container = makeContainer([
      _src('main', tier: 'mainstream'),
      _src('deep', tier: 'deep'),
      _src('indie', independence: 0.9, bias: 'alternative'),
    ]);
    await tester.pumpWidget(buildTestWidget(container));
    await tester.pumpAndSettle();

    expect(find.text(OnboardingStrings.swipeTitle), findsOneWidget);
    // La carte du dessus + ses boutons d'action (like / pas pour moi).
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    // Nudge « touchez pour explorer » sur la 1ère carte.
    expect(find.text(OnboardingStrings.swipeTapHint), findsOneWidget);
    // Bloc d'infos intrinsèques clair (Tendance + Fiabilité) sur la carte du dessus.
    expect(find.text(OnboardingStrings.swipeBiasPrefix), findsWidgets);
    expect(find.text(OnboardingStrings.swipeReliabilityPrefix), findsWidgets);
  });

  testWidgets('like (carte unique) : fling, vote enregistré, avance vers sources',
      (tester) async {
    final container = makeContainer([_src('solo', tier: 'mainstream')]);
    await tester.pumpWidget(buildTestWidget(container));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithIcon(InkWell, Icons.favorite_rounded));
    await tester.pump(); // démarre le fling
    await tester.pump(const Duration(milliseconds: 400)); // fling terminé → vote

    // Dernière carte triée → moment « on affine vos sources » (overlay ~1,4 s).
    expect(find.text(OnboardingStrings.swipeRefiningTitle), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1500)); // refining → completeSwipe
    expect(container.read(onboardingProvider).answers.swipeLiked,
        equals(['solo']));

    await tester.pump(const Duration(milliseconds: 350)); // transition completeSwipe
    expect(
      container.read(onboardingProvider).currentQuestionIndex,
      Section3Question.sources.index,
    );
  });

  testWidgets('skip (carte unique) : fling, rejet enregistré, avance vers sources',
      (tester) async {
    final container = makeContainer([_src('solo', tier: 'mainstream')]);
    await tester.pumpWidget(buildTestWidget(container));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithIcon(InkWell, Icons.close_rounded));
    await tester.pump(); // démarre le fling
    await tester.pump(const Duration(milliseconds: 400)); // fling terminé → vote

    // Dernière carte triée → moment « on affine vos sources » (overlay ~1,4 s).
    expect(find.text(OnboardingStrings.swipeRefiningTitle), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1500)); // refining → completeSwipe
    expect(container.read(onboardingProvider).answers.swipeDisliked,
        equals(['solo']));
    expect(container.read(onboardingProvider).answers.swipeLiked, isEmpty);

    await tester.pump(const Duration(milliseconds: 350)); // transition completeSwipe
    expect(
      container.read(onboardingProvider).currentQuestionIndex,
      Section3Question.sources.index,
    );
  });

  // Deck large et étalé (~8-10 cartes) pour exercer le compteur et la phrase
  // inline « ce qu'on retient ».
  List<Source> _richDeck() => [
        _src('deep-1', tier: 'deep'),
        _src('deep-2', tier: 'deep'),
        _src('indie-1', independence: 0.9, bias: 'alternative'),
        _src('indie-2', independence: 0.8, bias: 'specialized'),
        _src('est-1', independence: 0.2),
        _src('est-2', independence: 0.3),
        _src('main-1', tier: 'mainstream'),
        _src('main-2', tier: 'mainstream'),
        _src('left-1', bias: 'left'),
        _src('right-1', bias: 'right'),
      ];

  testWidgets('compteur humanisé + pas de chips de profil au départ',
      (tester) async {
    final container = makeContainer(_richDeck());
    await tester.pumpWidget(buildTestWidget(container));
    await tester.pumpAndSettle();

    // Nouveau titre.
    expect(find.text('Quels médias suivre ?'), findsOneWidget);
    // Compteur humanisé (palier « début »), plus jamais l'ancien « Carte X sur Y ».
    expect(find.textContaining('Premières cartes'), findsOneWidget);
    expect(find.textContaining('Carte '), findsNothing);
    // Aucun vote encore → la phrase inline « ce qu'on retient » est absente.
    expect(find.textContaining(OnboardingStrings.swipeProfileInline),
        findsNothing);
  });

  testWidgets('phrase inline « ce qu\'on retient » apparaît après un vote net-positif',
      (tester) async {
    final container = makeContainer(_richDeck());
    await tester.pumpWidget(buildTestWidget(container));
    await tester.pumpAndSettle();

    // Like la carte du dessus (mainstream par défaut le plus suivi) → un pôle
    // passe net-positif → la phrase inline s'affiche sous le deck.
    await tester.tap(find.widgetWithIcon(InkWell, Icons.favorite_rounded));
    await tester.pump(); // démarre le fling
    await tester.pump(const Duration(milliseconds: 400)); // fling → vote
    await tester.pumpAndSettle();

    expect(find.textContaining(OnboardingStrings.swipeProfileInline),
        findsOneWidget);
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
