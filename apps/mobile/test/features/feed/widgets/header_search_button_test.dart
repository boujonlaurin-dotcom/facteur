import 'dart:async';

import 'package:facteur/config/theme.dart';
import 'package:facteur/core/providers/analytics_provider.dart';
import 'package:facteur/core/services/analytics_service.dart';
import 'package:facteur/features/custom_topics/models/topic_models.dart';
import 'package:facteur/features/custom_topics/providers/custom_topics_provider.dart';
import 'package:facteur/features/feed/providers/feed_provider.dart';
import 'package:facteur/features/feed/providers/trending_topics_provider.dart';
import 'package:facteur/features/feed/widgets/header_search_button.dart';
import 'package:facteur/features/my_interests/models/user_sources_state.dart';
import 'package:facteur/features/my_interests/providers/user_sources_state_provider.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/features/sources/providers/sources_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Enregistre les filtres appliqués sans toucher au réseau.
class _RecordingFeedNotifier extends FeedNotifier {
  static final calls = <String>[];

  @override
  FutureOr<FeedState> build() async => FeedState(items: const []);

  @override
  Future<void> setKeyword(String? keyword,
      {bool includeUnfollowed = false}) async {
    calls.add('keyword:$keyword');
  }

  @override
  Future<void> clearFilters() async {
    calls.add('clearFilters');
  }
}

Source _source({required String id, required String name}) =>
    Source.fallback().copyWith(id: id, name: name);

class _StubCatalog extends UserSourcesNotifier {
  _StubCatalog(this._sources);
  final List<Source> _sources;

  @override
  Future<List<Source>> build() async => _sources;
}

class _StubSourcesState extends UserSourcesStateNotifier {
  @override
  Future<UserSourcesState> build() async => const UserSourcesState(
        sources: [],
        favorites: [],
        favoriteCount: 0,
        favoriteCap: 5,
      );
}

class _StubTopics extends CustomTopicsNotifier {
  @override
  Future<List<UserTopicProfile>> build() async => const <UserTopicProfile>[];
}

Widget _host({
  FeedFilterSelection selection = FeedFilterSelection.empty,
  List<Source> catalog = const <Source>[],
  bool isEssentielTab = false,
}) {
  return ProviderScope(
    overrides: [
      feedProvider.overrideWith(_RecordingFeedNotifier.new),
      feedFilterSelectionProvider.overrideWith((ref) => selection),
      userSourcesProvider.overrideWith(() => _StubCatalog(catalog)),
      userSourcesStateProvider.overrideWith(_StubSourcesState.new),
      customTopicsProvider.overrideWith(_StubTopics.new),
      trendingTopicsProvider.overrideWith((ref) async => <TrendingTopic>[]),
      analyticsServiceProvider.overrideWithValue(AnalyticsService.disabled()),
    ],
    child: MaterialApp(
      theme: ThemeData(
        extensions: [FacteurPalettes.light],
        splashFactory: NoSplash.splashFactory,
      ),
      home: Scaffold(
        body: Center(child: HeaderSearchButton(isEssentielTab: isEssentielTab)),
      ),
    ),
  );
}

Finder get _clearButton => find.bySemanticsLabel('Effacer le filtre');
// RegExp (contains) : dans l'état pill, le libellé « Rechercher » est fusionné
// avec le texte du filtre dans le même nœud sémantique.
Finder get _searchButton => find.bySemanticsLabel(RegExp('Rechercher'));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _RecordingFeedNotifier.calls.clear();
  });

  testWidgets('sans filtre actif : loupe simple, aucun ✕', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(_searchButton, findsOneWidget);
    expect(_clearButton, findsNothing);
    expect(find.byIcon(PhosphorIcons.x(PhosphorIconsStyle.bold)), findsNothing);
  });

  testWidgets('mot-clé actif : pill teintée avec ✕', (tester) async {
    await tester.pumpWidget(
      _host(selection: const FeedFilterSelection(keyword: 'retraites')),
    );
    await tester.pumpAndSettle();

    expect(_clearButton, findsOneWidget);
    expect(find.text('retraites'), findsOneWidget);

    final icon = tester.widget<Icon>(
      find.byIcon(PhosphorIcons.magnifyingGlass(PhosphorIconsStyle.bold)),
    );
    expect(icon.color, FacteurPalettes.light.primary);
  });

  testWidgets('filtre source (même non favori) : pill avec le nom de la source',
      (tester) async {
    await tester.pumpWidget(
      _host(
        selection: const FeedFilterSelection(sourceId: 's-mediapart'),
        catalog: [_source(id: 's-mediapart', name: 'Mediapart')],
      ),
    );
    await tester.pumpAndSettle();

    // Régression clé : le header ne suivait que `keyword` et repassait en icône
    // neutre sur un filtre source/thème/sujet.
    expect(_clearButton, findsOneWidget);
    expect(find.text('Mediapart'), findsOneWidget);
  });

  testWidgets('filtre thème : pill avec le libellé lisible du thème',
      (tester) async {
    await tester.pumpWidget(
      _host(selection: const FeedFilterSelection(theme: 'tech')),
    );
    await tester.pumpAndSettle();

    expect(_clearButton, findsOneWidget);
    expect(find.text('Technologie'), findsOneWidget);
  });

  testWidgets('tap ✕ appelle clearFilters() sans ouvrir la sheet',
      (tester) async {
    await tester.pumpWidget(
      _host(selection: const FeedFilterSelection(sourceId: 's-mediapart'),
          catalog: [_source(id: 's-mediapart', name: 'Mediapart')]),
    );
    await tester.pumpAndSettle();

    await tester.tap(_clearButton);
    await tester.pumpAndSettle();

    expect(_RecordingFeedNotifier.calls, ['clearFilters']);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('tap loupe ouvre la recherche (onglet Flâner)', (tester) async {
    await tester.pumpWidget(
      _host(selection: const FeedFilterSelection(keyword: 'retraites')),
    );
    await tester.pumpAndSettle();

    await tester.tap(_searchButton);
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(_RecordingFeedNotifier.calls, isEmpty);
  });

  testWidgets('isEssentielTab: true — la pill de filtre reste montée',
      (tester) async {
    await tester.pumpWidget(
      _host(
        selection: const FeedFilterSelection(keyword: 'retraites'),
        isEssentielTab: true,
      ),
    );
    await tester.pumpAndSettle();

    // Sur L'Essentiel la barre de filtres n'existe pas : la loupe du header est
    // la seule affordance qui signale (et efface) un filtre actif.
    expect(_clearButton, findsOneWidget);
    expect(find.text('retraites'), findsOneWidget);
  });
}
