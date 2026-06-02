import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/sources/models/smart_search_result.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/features/sources/providers/sources_providers.dart';
import 'package:facteur/features/sources/repositories/sources_repository.dart';
import 'package:facteur/features/sources/widgets/source_add_panel.dart';

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
}
