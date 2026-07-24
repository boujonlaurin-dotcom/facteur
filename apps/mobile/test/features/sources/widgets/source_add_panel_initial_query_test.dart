import 'package:facteur/config/theme.dart';
import 'package:facteur/core/providers/analytics_provider.dart';
import 'package:facteur/core/services/analytics_service.dart';
import 'package:facteur/features/sources/models/smart_search_result.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/features/sources/providers/sources_providers.dart';
import 'package:facteur/features/sources/repositories/sources_repository.dart';
import 'package:facteur/features/sources/widgets/source_add_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubCatalog extends UserSourcesNotifier {
  @override
  Future<List<Source>> build() async => const [];
}

/// Le vrai repository construit un `ApiClient(Supabase.instance.client)` —
/// impossible en test unitaire. Seul `logSearchAbandoned` (appelé au dispose du
/// panneau) est réellement emprunté ici.
class _FakeSourcesRepository implements SourcesRepository {
  @override
  Future<void> logSearchAbandoned(String query) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Story 30.1 — le pont depuis la recherche universelle doit atterrir sur des
/// résultats, pas sur un champ vide. On enregistre donc la requête réellement
/// envoyée à la recherche intelligente.
void main() {
  late List<String> searched;

  Widget host({String? initialQuery}) {
    searched = [];
    return ProviderScope(
      overrides: [
        sourcesRepositoryProvider.overrideWithValue(_FakeSourcesRepository()),
        userSourcesProvider.overrideWith(() => _StubCatalog()),
        trendingSourcesProvider.overrideWith((ref) async => <Source>[]),
        analyticsServiceProvider.overrideWithValue(AnalyticsService.disabled()),
        smartSearchProvider.overrideWith((ref, params) async {
          searched.add(params.query);
          return SmartSearchResponse(
            queryNormalized: params.query,
            results: const [],
            layersCalled: const ['catalog'],
          );
        }),
      ],
      child: MaterialApp(
        theme: ThemeData(
          extensions: [FacteurPalettes.light],
          splashFactory: NoSplash.splashFactory,
        ),
        home: Scaffold(
          body: SourceAddPanel(
            initialQuery: initialQuery,
            showCommunityGems: false,
          ),
        ),
      ),
    );
  }

  testWidgets('sans initialQuery, le champ est vide et rien n\'est cherché',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, isEmpty);
    expect(searched, isEmpty);
  });

  testWidgets('initialQuery pré-remplit le champ ET lance la recherche',
      (tester) async {
    await tester.pumpWidget(host(initialQuery: 'gazette locale'));
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, 'gazette locale');
    expect(searched, contains('gazette locale'));
  });

  testWidgets('une initialQuery blanche est ignorée', (tester) async {
    await tester.pumpWidget(host(initialQuery: '   '));
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, isEmpty);
    expect(searched, isEmpty);
  });
}
