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
import 'package:facteur/features/onboarding/screens/questions/sources_question.dart';
import 'package:facteur/features/onboarding/widgets/source_recommendation_card.dart';
import 'package:facteur/features/sources/models/smart_search_result.dart';
import 'package:facteur/features/sources/models/source_model.dart';
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

/// 9 sources curées « tech » : matched pour des thèmes tech, followerCount
/// croissant pour vérifier le tri et le cap à 7.
List<Source> _makeTechSources() => List.generate(9, (i) {
      return Source(
        id: 'src-$i',
        name: 'Source $i',
        type: SourceType.article,
        theme: 'tech',
        isCurated: true,
        followerCount: 100 - i,
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
    final container = ProviderContainer(overrides: [
      userSourcesProvider.overrideWith(() => _FakeUserSourcesNotifier(sources)),
      sourcesRepositoryProvider.overrideWithValue(_FakeSourcesRepository()),
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
        home: const Scaffold(body: SourcesQuestion()),
      ),
    );
  }

  testWidgets(
      'variante curieux : max 7 suggestions pré-cochées, panneau replié',
      (tester) async {
    final container = makeContainer(_makeTechSources());
    // bypassOnboarding pose themes=[tech, international] + intent curious.
    container.read(onboardingProvider.notifier).bypassOnboarding();

    await tester.pumpWidget(buildTestWidget(container));
    await tester.pumpAndSettle();

    // Cap à 7 suggestions (9 sources matched disponibles).
    expect(find.byType(SourceRecommendationCard), findsNWidgets(7));
    expect(
      find.textContaining(OnboardingStrings.sourcesSuggestionsTitle),
      findsOneWidget,
    );

    // Pré-sélection = les 7 visibles.
    expect(
      find.text(OnboardingStrings.selectedCount(7)),
      findsOneWidget,
    );

    // Panneau d'ajout replié derrière son en-tête.
    expect(
      find.text(OnboardingStrings.sourcesAlreadyFollowTitle),
      findsOneWidget,
    );
    expect(find.byType(SourceAddPanel), findsNothing);

    // Catalogue replié.
    expect(
      find.text(OnboardingStrings.sourcesSeeAllCatalog),
      findsOneWidget,
    );

  });

  testWidgets(
      'variante je connais : panneau proéminent, suggestions repliées à 5, '
      'aucune pré-sélection', (tester) async {
    final container = makeContainer(_makeTechSources());
    final notifier = container.read(onboardingProvider.notifier);
    notifier.bypassOnboarding();
    notifier.selectSourcesIntent('knows');

    await tester.pumpWidget(buildTestWidget(container));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    // Panneau de recherche visible d'entrée.
    expect(find.byType(SourceAddPanel), findsOneWidget);
    expect(find.text(OnboardingStrings.sourcesKnowsTitle), findsOneWidget);

    // Suggestions repliées : 5 visibles + « Voir plus ».
    expect(find.byType(SourceRecommendationCard), findsNWidgets(5));
    expect(find.text(OnboardingStrings.sourcesSeeMore), findsOneWidget);
    expect(find.textContaining(OnboardingStrings.sourcesGuideMeTitle), findsOneWidget);

    // Aucune pré-sélection : le CTA affiche « Passer ».
    expect(find.text(OnboardingStrings.skipButton), findsOneWidget);

    // « Voir plus » déplie le reste (7 au total).
    await tester.ensureVisible(find.text(OnboardingStrings.sourcesSeeMore));
    await tester.tap(find.text(OnboardingStrings.sourcesSeeMore));
    await tester.pumpAndSettle();
    expect(find.byType(SourceRecommendationCard), findsNWidgets(7));

  });

  testWidgets('skip intent (défaut curious) : suggestions affichées',
      (tester) async {
    final container = makeContainer(_makeTechSources());
    final notifier = container.read(onboardingProvider.notifier);
    notifier.bypassOnboarding();
    // sourcesIntent reste 'curious' (défaut bypass) — la page doit matcher.

    await tester.pumpWidget(buildTestWidget(container));
    await tester.pumpAndSettle();

    expect(
      find.textContaining(OnboardingStrings.sourcesSuggestionsTitle),
      findsOneWidget,
    );

  });
}
