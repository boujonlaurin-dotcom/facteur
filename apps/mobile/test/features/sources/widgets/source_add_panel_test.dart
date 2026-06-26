import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/sources/models/smart_search_result.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/features/sources/providers/sources_providers.dart';
import 'package:facteur/features/sources/repositories/sources_repository.dart';
import 'package:facteur/features/sources/widgets/example_chips.dart';
import 'package:facteur/features/sources/widgets/source_add_panel.dart';

/// Catalogue figé (sources curées) sans réseau — pour l'empty-state thémé.
class _FakeUserSources extends UserSourcesNotifier {
  _FakeUserSources(this._sources);
  final List<Source> _sources;

  @override
  Future<List<Source>> build() async => _sources;
}

Source _curated(String id, String name, String theme) => Source(
      id: id,
      name: name,
      type: SourceType.article,
      theme: theme,
      isCurated: true,
    );

class _FakeSourcesRepository implements SourcesRepository {
  final SmartSearchResult result;
  int trustCalls = 0;
  int addCustomCalls = 0;

  _FakeSourcesRepository(this.result);

  @override
  Future<SmartSearchResponse> smartSearch(
    String query, {
    String? contentType,
    bool expand = false,
  }) async {
    return SmartSearchResponse(
      queryNormalized: query,
      results: [result],
      layersCalled: const ['catalog'],
    );
  }

  @override
  Future<List<Source>> getAllSources() async => const [];

  @override
  Future<void> trustSource(String sourceId) async {
    trustCalls++;
  }

  @override
  Future<void> addCustomSource(String url, {String? name}) async {
    addCustomCalls++;
  }

  @override
  Future<void> logSearchAbandoned(String query) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} non mocké');
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('veilleMode remonte la source sans trust ni ajout global', (
    tester,
  ) async {
    const result = SmartSearchResult(
      name: 'Le Monde',
      type: 'article',
      url: 'https://www.lemonde.fr',
      feedUrl: 'https://www.lemonde.fr/rss/une.xml',
      inCatalog: true,
      sourceId: 'src-1',
    );
    final repo = _FakeSourcesRepository(result);
    SmartSearchResult? added;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sourcesRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: FacteurTheme.lightTheme,
          home: Scaffold(
            body: SourceAddPanel(
              showIntro: false,
              showCommunityGems: false,
              showAddedNudge: false,
              veilleMode: true,
              onSourceAdded: (result) => added = result,
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'le monde');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('Le Monde'), findsOneWidget);
    await tester.tap(find.text('Ajouter'));
    await tester.pumpAndSettle();

    expect(added?.sourceId, 'src-1');
    expect(repo.trustCalls, 0);
    expect(repo.addCustomCalls, 0);
  });

  testWidgets(
      'inlineProof : ajout catalogue → carte « Connecté » sans modale, '
      'liste conservée', (tester) async {
    const result = SmartSearchResult(
      name: 'Le Monde',
      type: 'article',
      url: 'https://www.lemonde.fr',
      feedUrl: 'https://www.lemonde.fr/rss/une.xml',
      inCatalog: true,
      sourceId: 'src-1',
      recentItems: [
        SmartSearchRecentItem(title: 'Article un'),
        SmartSearchRecentItem(title: 'Article deux'),
      ],
    );
    final repo = _FakeSourcesRepository(result);
    SmartSearchResult? added;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sourcesRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: FacteurTheme.lightTheme,
          home: Scaffold(
            body: SourceAddPanel(
              showIntro: false,
              showCommunityGems: false,
              showAddedNudge: false,
              inlineProof: true,
              onSourceAdded: (result) => added = result,
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'le monde');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('Le Monde'), findsOneWidget);
    await tester.tap(find.text('Ajouter'));
    await tester.pumpAndSettle();

    // Ajout serveur effectué, callback remonté.
    expect(repo.trustCalls, 1);
    expect(added?.sourceId, 'src-1');

    // Pas de modale détail : la carte transformée reste dans la liste.
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Connecté'), findsOneWidget);
    expect(find.text('Article un'), findsOneWidget);
    expect(find.text('Article deux'), findsOneWidget);

    // La recherche n'est pas réinitialisée (le champ garde la requête).
    expect(find.widgetWithText(TextField, 'le monde'), findsOneWidget);
  });

  testWidgets(
      'initialCatalogTheme : catalogue filtré rendu EN TÊTE de l\'empty-state '
      '(déplié + avant les exemples) — raccourci thème (#3)', (tester) async {
    const dummy = SmartSearchResult(
      name: 'x',
      type: 'article',
      url: 'https://x.test',
      feedUrl: 'https://x.test/rss',
    );
    final repo = _FakeSourcesRepository(dummy);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sourcesRepositoryProvider.overrideWithValue(repo),
          userSourcesProvider.overrideWith(
            () => _FakeUserSources([
              _curated('s1', 'Numerama', 'tech'),
              _curated('s2', 'Le Monde', 'politics'),
            ]),
          ),
        ],
        child: MaterialApp(
          theme: FacteurTheme.lightTheme,
          home: const Scaffold(
            body: SourceAddPanel(
              showIntro: false,
              // Indépendant des pépites : le catalogue thémé s'affiche quand même.
              showCommunityGems: false,
              showAddedNudge: false,
              initialCatalogTheme: 'tech',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Catalogue déplié d'emblée et filtré sur 'tech' (Numerama, pas Le Monde).
    // (Numerama apparaît ≥1× : tuile + repli du logo-avatar sur le nom.)
    expect(find.text('Toutes les sources déjà ajoutées'), findsOneWidget);
    expect(find.text('Numerama'), findsWidgets);
    expect(find.text('Le Monde'), findsNothing);

    // Rendu AVANT les exemples : le catalogue est le contenu de tête.
    final catalogY =
        tester.getTopLeft(find.text('Toutes les sources déjà ajoutées')).dy;
    final examplesY = tester.getTopLeft(find.byType(ExampleChips)).dy;
    expect(catalogY, lessThan(examplesY));
  });
}
