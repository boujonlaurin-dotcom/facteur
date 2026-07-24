import 'dart:async';

import 'package:facteur/config/routes.dart';
import 'package:facteur/config/theme.dart';
import 'package:facteur/core/providers/analytics_provider.dart';
import 'package:facteur/core/services/analytics_service.dart';
import 'package:facteur/features/custom_topics/models/topic_models.dart';
import 'package:facteur/features/custom_topics/providers/custom_topics_provider.dart';
import 'package:facteur/features/feed/providers/feed_provider.dart';
import 'package:facteur/features/feed/providers/trending_topics_provider.dart';
import 'package:facteur/features/feed/widgets/search_filter_sheet.dart';
import 'package:facteur/features/my_interests/models/user_sources_state.dart';
import 'package:facteur/features/my_interests/providers/user_sources_state_provider.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/features/sources/providers/sources_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Enregistre les filtres appliqués sans toucher au réseau.
class _RecordingFeedNotifier extends FeedNotifier {
  static final calls = <String>[];

  @override
  FutureOr<FeedState> build() async => FeedState(items: const []);

  @override
  Future<void> setKeyword(String? keyword, {bool includeUnfollowed = false}) async {
    calls.add('keyword:$keyword:$includeUnfollowed');
  }

  @override
  Future<void> setSource(String? sourceId) async => calls.add('source:$sourceId');

  @override
  Future<void> setTopic(String? topic) async => calls.add('topic:$topic');

  @override
  Future<void> setTheme(String? theme) async => calls.add('theme:$theme');

  @override
  Future<void> setEntity(String? entity) async => calls.add('entity:$entity');
}

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
  _StubTopics(this._topics);
  final List<UserTopicProfile> _topics;

  @override
  Future<List<UserTopicProfile>> build() async => _topics;
}

Source _source(
  String id,
  String name, {
  bool isTrusted = false,
  String? url,
}) =>
    Source(
      id: id,
      name: name,
      url: url,
      type: SourceType.article,
      isTrusted: isTrusted,
    );

final _sources = [
  _source('s1', 'Mediapart', isTrusted: true),
  _source('s2', 'Le Monde', url: 'https://lemonde.fr'),
];

final _topics = [
  UserTopicProfile(id: 't1', name: 'Écologie', slugParent: 'environment'),
];

/// Hôte minimal : GoRouter (la sheet lit la route courante) + palette Facteur.
Widget _host({String initialLocation = RoutePaths.flaner}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: RoutePaths.flaner,
        builder: (_, __) => const _SheetHost(),
      ),
      GoRoute(
        path: '/settings/sources/add',
        name: RouteNames.addSource,
        builder: (_, __) => const Scaffold(body: Text('ADD SOURCE SCREEN')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      feedProvider.overrideWith(_RecordingFeedNotifier.new),
      userSourcesProvider.overrideWith(() => _StubCatalog(_sources)),
      userSourcesStateProvider.overrideWith(() => _StubSourcesState()),
      customTopicsProvider.overrideWith(() => _StubTopics(_topics)),
      trendingTopicsProvider.overrideWith((ref) async => <TrendingTopic>[]),
      analyticsServiceProvider.overrideWithValue(AnalyticsService.disabled()),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      theme: ThemeData(
        extensions: [FacteurPalettes.light],
        splashFactory: NoSplash.splashFactory,
      ),
    ),
  );
}

class _SheetHost extends StatelessWidget {
  const _SheetHost();

  /// Compte les appels `onApplied` — c'est le hôte, pas la sheet, qui décide
  /// de naviguer après l'application d'un filtre.
  static int applied = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () => SearchFilterSheet.show(
                context,
                onApplied: () => applied++,
              ),
              child: const Text('OUVRIR'),
            ),
            ElevatedButton(
              onPressed: () => SearchFilterSheet.show(
                context,
                currentKeyword: 'retraites',
                onApplied: () => applied++,
              ),
              child: const Text('OUVRIR AVEC RECHERCHE'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.pumpWidget(_host());
  await tester.pumpAndSettle();
  await tester.tap(find.text('OUVRIR'));
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  // Debounce interne de la sheet (180 ms).
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _RecordingFeedNotifier.calls.clear();
    _SheetHost.applied = 0;
  });

  testWidgets('query vide → aucune section de résultats', (tester) async {
    await _openSheet(tester);
    expect(find.text('Rechercher'), findsOneWidget);
    expect(find.text('ARTICLES'), findsNothing);
    expect(find.text('TES SOURCES'), findsNothing);
  });

  testWidgets('une requête libre ouvre sur la recherche d\'articles',
      (tester) async {
    await _openSheet(tester);
    await _type(tester, 'retraites');

    expect(find.text('ARTICLES'), findsOneWidget);
    expect(find.text('Rechercher « retraites »'), findsOneWidget);
    expect(find.text('AJOUTER UNE SOURCE'), findsOneWidget);
  });

  testWidgets('taper le nom d\'une source suivie la propose en filtre',
      (tester) async {
    await _openSheet(tester);
    await _type(tester, 'mediapart');

    expect(find.text('TES SOURCES'), findsOneWidget);
    await tester.tap(find.text('Mediapart'));
    await tester.pumpAndSettle();

    expect(_RecordingFeedNotifier.calls, contains('source:s1'));
  });

  testWidgets('taper un thème le propose en filtre', (tester) async {
    await _openSheet(tester);
    await _type(tester, 'environnement');

    expect(find.text('THÈMES'), findsOneWidget);
    await tester.tap(find.text('Environnement'));
    await tester.pumpAndSettle();

    expect(_RecordingFeedNotifier.calls, contains('theme:environment'));
  });

  testWidgets('taper un sujet suivi le propose en filtre', (tester) async {
    await _openSheet(tester);
    await _type(tester, 'ecolo');

    expect(find.text('SUJETS SUIVIS'), findsOneWidget);
    await tester.tap(find.text('Écologie'));
    await tester.pumpAndSettle();

    expect(_RecordingFeedNotifier.calls, contains('topic:environment'));
  });

  testWidgets('une source du catalogue non suivie s\'ajoute en 1 tap',
      (tester) async {
    await _openSheet(tester);
    await _type(tester, 'Le Monde');

    expect(find.text('AJOUTER UNE SOURCE'), findsOneWidget);
    expect(find.text('Pas encore dans tes sources'), findsOneWidget);
    expect(find.text('Ajouter'), findsOneWidget);
  });

  testWidgets('un domaine bascule la sheet en intention source',
      (tester) async {
    await _openSheet(tester);
    await _type(tester, 'lemonde.fr');

    // « Articles » est relégué en fin de liste : chercher un domaine dans les
    // titres d'articles n'a aucun sens.
    final headers = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .whereType<String>()
        .where((s) => s == 'ARTICLES' || s == 'AJOUTER UNE SOURCE')
        .toList();
    expect(headers.first, 'AJOUTER UNE SOURCE');
    expect(headers.last, 'ARTICLES');
  });

  testWidgets('le CTA web ouvre l\'ajout de source avec la requête',
      (tester) async {
    await _openSheet(tester);
    await _type(tester, 'gazette locale');

    await tester.tap(find.text('Chercher « gazette locale » sur le web'));
    await tester.pumpAndSettle();

    expect(find.text('ADD SOURCE SCREEN'), findsOneWidget);
  });

  testWidgets('valider au clavier lance la recherche mot-clé', (tester) async {
    await _openSheet(tester);
    await tester.enterText(find.byType(TextField), 'retraites');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(_RecordingFeedNotifier.calls, contains('keyword:retraites:false'));
  });

  testWidgets('la sheet ne navigue pas elle-même : elle notifie le hôte',
      (tester) async {
    await _openSheet(tester);
    await _type(tester, 'mediapart');
    await tester.tap(find.text('Mediapart'));
    await tester.pumpAndSettle();

    expect(_SheetHost.applied, 1);
    // Toujours sur l'écran hôte : aucun `go` déclenché par la sheet.
    expect(find.text('OUVRIR'), findsOneWidget);
  });

  testWidgets('sans recherche active, pas de CTA « effacer »', (tester) async {
    await _openSheet(tester);
    expect(find.text('Effacer la recherche'), findsNothing);
  });

  testWidgets('« effacer la recherche » vide le mot-clé', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
    await tester.tap(find.text('OUVRIR AVEC RECHERCHE'));
    await tester.pumpAndSettle();

    expect(find.text('Effacer la recherche'), findsOneWidget);
    await tester.tap(find.text('Effacer la recherche'));
    await tester.pumpAndSettle();

    expect(_RecordingFeedNotifier.calls, contains('keyword:null:false'));
    expect(_SheetHost.applied, 1);
  });
}
