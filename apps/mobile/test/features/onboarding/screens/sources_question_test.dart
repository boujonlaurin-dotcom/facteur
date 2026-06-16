import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/core/providers/analytics_provider.dart';
import 'package:facteur/core/services/analytics_service.dart';
import 'package:facteur/features/onboarding/onboarding_strings.dart';
import 'package:facteur/features/onboarding/data/source_recommender.dart';
import 'package:facteur/features/onboarding/providers/onboarding_provider.dart';
import 'package:facteur/features/onboarding/screens/questions/sources_question.dart';
import 'package:facteur/features/onboarding/widgets/recommendation_section.dart';
import 'package:facteur/features/onboarding/widgets/source_recommendation_card.dart';
import 'package:facteur/features/sources/models/smart_search_result.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/features/sources/models/source_profile.dart';
import 'package:facteur/features/sources/providers/sources_providers.dart';
import 'package:facteur/features/sources/repositories/sources_repository.dart';
import 'package:facteur/features/sources/widgets/source_add_panel.dart';

class _FakeUserSourcesNotifier extends UserSourcesNotifier {
  _FakeUserSourcesNotifier(this._sources);
  final List<Source> _sources;

  @override
  Future<List<Source>> build() async => _sources;
}

class _FakeSourcesRepository implements SourcesRepository {
  @override
  Future<SmartSearchResponse> smartSearch(
    String query, {
    String? contentType,
    bool expand = false,
  }) async {
    return SmartSearchResponse(queryNormalized: query, results: const []);
  }

  @override
  Future<List<Source>> getAllSources() async => const [];

  @override
  Future<void> logSearchAbandoned(String query) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} non mocké');
}

/// 15 sources curées « tech » (= cap matched), toutes suggérées : matched pour
/// le thème tech, followerCount décroissant pour exercer le tri volume-proxy.
/// La première est un gros publieur mainstream (« Grand Média », fort
/// followerCount) qu'on doit retrouver dans les suggestions.
List<Source> _makeTechSources() => List.generate(15, (i) {
  return Source(
    id: 'src-$i',
    name: i == 0 ? 'Grand Média' : 'Source $i',
    type: SourceType.article,
    theme: 'tech',
    isCurated: true,
    sourceTier: 'mainstream',
    followerCount: i == 0 ? 100000 : 100 - i,
    reliabilityScore: 'high',
  );
});

void main() {
  // Hive est initialisé mais la box n'est jamais ouverte hors zone de test :
  // les openBox/put de l'OnboardingNotifier (lancés dans la zone fake-async
  // de testWidgets) restent en attente sans bloquer les tests suivants, et
  // chaque test repart d'un état vierge.
  setUpAll(() {
    Hive.init(Directory.systemTemp.createTempSync('onb_sources_test').path);
  });

  ProviderContainer makeContainer(List<Source> sources) {
    final container = ProviderContainer(
      overrides: [
        userSourcesProvider.overrideWith(
          () => _FakeUserSourcesNotifier(sources),
        ),
        for (final source in sources)
          sourceProfileProvider(
            source.id,
          ).overrideWith((_) async => const SourceProfile()),
        sourcesRepositoryProvider.overrideWithValue(_FakeSourcesRepository()),
        analyticsServiceProvider.overrideWithValue(AnalyticsService.disabled()),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Widget buildTestWidget(ProviderContainer container) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: FacteurTheme.lightTheme,
        home: const Scaffold(body: SourcesQuestion()),
      ),
    );
  }

  testWidgets('4 blocs numérotés, ≤18 suggestions, top 9 pré-cochées', (
    tester,
  ) async {
    final container = makeContainer(_makeTechSources());
    // bypassOnboarding pose themes=[tech, international].
    container.read(onboardingProvider.notifier).bypassOnboarding();

    await tester.pumpWidget(buildTestWidget(container));
    await tester.pumpAndSettle();

    // Les 4 blocs numérotés ①②③④ sont présents.
    expect(find.byType(RecommendationSectionHeader), findsNWidgets(4));

    // 15 sources matched → 15 cartes suggestions (≤ 18, catalogue replié donc
    // sans cartes additionnelles).
    final cards = find.byType(SourceRecommendationCard);
    expect(tester.widgetList(cards).length, lessThanOrEqualTo(18));
    expect(cards, findsNWidgets(15));

    // Pré-sélection = top 9 uniquement (le reste affiché décoché).
    expect(find.text(OnboardingStrings.selectedCount(9)), findsOneWidget);

    // Le gros publieur mainstream remonte dans les suggestions (volume-proxy).
    expect(find.text('Grand Média'), findsOneWidget);

    // Bloc ② : panneau d'ajout replié derrière son en-tête.
    expect(
      find.text(OnboardingStrings.sourcesAlreadyFollowTitle),
      findsOneWidget,
    );
    expect(find.byType(SourceAddPanel), findsNothing);

    // Bloc ③ : catalogue replié.
    expect(find.text(OnboardingStrings.sourcesSeeAllCatalog), findsOneWidget);
  });

  testWidgets('panneau d\'ajout dépliable : SourceAddPanel monté au tap', (
    tester,
  ) async {
    final container = makeContainer(_makeTechSources());
    container.read(onboardingProvider.notifier).bypassOnboarding();

    await tester.pumpWidget(buildTestWidget(container));
    await tester.pumpAndSettle();

    // Replié au départ.
    expect(find.byType(SourceAddPanel), findsNothing);

    // Déplier « Vous suivez déjà un média ? » → panneau monté.
    await tester.ensureVisible(
      find.text(OnboardingStrings.sourcesAlreadyFollowTitle),
    );
    await tester.tap(find.text(OnboardingStrings.sourcesAlreadyFollowTitle));
    await tester.pumpAndSettle();
    expect(find.byType(SourceAddPanel), findsOneWidget);
  });

  testWidgets(
    'sources likées : sélectionnées, récapitulées et retirées des suggestions',
    (tester) async {
      final liked = Source(
        id: 'sismique',
        name: 'Sismique',
        type: SourceType.article,
        theme: 'tech',
        isCurated: true,
        sourceTier: 'mainstream',
        reliabilityScore: 'high',
        followerCount: 5000,
      );
      final sources = [liked, ..._makeTechSources()];
      final container = makeContainer(sources);
      container.read(onboardingProvider.notifier).bypassOnboarding();
      container.read(onboardingProvider.notifier).completeSwipe(const [
        'sismique',
      ], const []);

      await tester.pumpWidget(buildTestWidget(container));
      await tester.pumpAndSettle();

      expect(find.text('Déjà ajoutées'), findsOneWidget);
      expect(find.text('Sismique'), findsOneWidget);
      expect(
        find.text(OnboardingStrings.selectedCount(10)),
        findsOneWidget,
        reason: '9 suggestions précochées + la source likée déjà validée',
      );

      final suggestionCards = tester
          .widgetList<SourceRecommendationCard>(
            find.byType(SourceRecommendationCard),
          )
          .toList();
      expect(
        suggestionCards.map((c) => c.recommendation.source.id),
        isNot(contains('sismique')),
      );
    },
  );

  testWidgets(
    'SourceRecommendationCard affiche le nombre de lecteurs Facteur',
    (tester) async {
      final source = Source(
        id: 'reader-count',
        name: 'Le Signal',
        type: SourceType.article,
        followerCount: 2,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: FacteurTheme.lightTheme,
          home: Scaffold(
            body: SourceRecommendationCard(
              recommendation: RecommendedSource(
                source: source,
                category: SourceCategory.matched,
              ),
              isSelected: false,
              onToggle: () {},
              onInfoTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('Suivi par 2 lecteurs Facteur'), findsOneWidget);
    },
  );
}
