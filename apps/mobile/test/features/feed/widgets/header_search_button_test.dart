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

Finder get _searchButton => find.bySemanticsLabel('Rechercher');
Finder get _searchIcon =>
    find.byIcon(PhosphorIcons.magnifyingGlass(PhosphorIconsStyle.bold));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _RecordingFeedNotifier.calls.clear();
  });

  testWidgets('sans filtre actif : loupe simple, aucun ✕', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(_searchButton, findsOneWidget);
    expect(_searchIcon, findsOneWidget);
    expect(find.byIcon(PhosphorIcons.x(PhosphorIconsStyle.bold)), findsNothing);
  });

  testWidgets('mot-clé actif : la loupe reste une icône simple, pas de pill',
      (tester) async {
    await tester.pumpWidget(
      _host(selection: const FeedFilterSelection(keyword: 'retraites')),
    );
    await tester.pumpAndSettle();

    expect(_searchButton, findsOneWidget);
    expect(_searchIcon, findsOneWidget);
    expect(find.text('retraites'), findsNothing);
    expect(find.byIcon(PhosphorIcons.x(PhosphorIconsStyle.bold)), findsNothing);
  });

  testWidgets(
      'filtre source (même non favori) : la loupe reste une icône simple',
      (tester) async {
    await tester.pumpWidget(
      _host(
        selection: const FeedFilterSelection(sourceId: 's-mediapart'),
        catalog: [_source(id: 's-mediapart', name: 'Mediapart')],
      ),
    );
    await tester.pumpAndSettle();

    expect(_searchButton, findsOneWidget);
    expect(_searchIcon, findsOneWidget);
    expect(find.text('Mediapart'), findsNothing);
  });

  testWidgets('filtre thème : la loupe reste une icône simple', (tester) async {
    await tester.pumpWidget(
      _host(selection: const FeedFilterSelection(theme: 'tech')),
    );
    await tester.pumpAndSettle();

    expect(_searchButton, findsOneWidget);
    expect(_searchIcon, findsOneWidget);
    expect(find.text('Technologie'), findsNothing);
  });

  testWidgets('tap loupe ouvre la sheet (onglet Flâner)', (tester) async {
    await tester.pumpWidget(
      _host(selection: const FeedFilterSelection(keyword: 'retraites')),
    );
    await tester.pumpAndSettle();

    await tester.tap(_searchButton);
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(_RecordingFeedNotifier.calls, isEmpty);
  });

  testWidgets('isEssentielTab: true — la loupe reste une icône simple',
      (tester) async {
    await tester.pumpWidget(
      _host(
        selection: const FeedFilterSelection(keyword: 'retraites'),
        isEssentielTab: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(_searchButton, findsOneWidget);
    expect(_searchIcon, findsOneWidget);
  });

  testWidgets('isEssentielTab: true — tap loupe ouvre la sheet', (tester) async {
    await tester.pumpWidget(
      _host(
        selection: const FeedFilterSelection(keyword: 'retraites'),
        isEssentielTab: true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(_searchButton);
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
  });
}
