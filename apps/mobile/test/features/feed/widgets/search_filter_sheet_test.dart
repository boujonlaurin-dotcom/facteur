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

  /// Si posé, `setKeyword` **attend** ce completer avant d'enregistrer son
  /// appel : permet de vérifier que `onApplied` part **avant** que `apply()`
  /// ne se résolve (ordre `pop → onApplied → await apply`).
  static Completer<void>? applyGate;

  @override
  FutureOr<FeedState> build() async => FeedState(items: const []);

  @override
  Future<void> setKeyword(String? keyword, {bool includeUnfollowed = false}) async {
    if (applyGate != null) await applyGate!.future;
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

  @override
  Future<void> clearFilters() async => calls.add('clearFilters');
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

/// Capture `search_result_selected` sans réseau — `query_length` et `rank`
/// pilotent le funnel de la story 30.1, ils doivent être exacts.
class _RecordingAnalytics extends AnalyticsService {
  _RecordingAnalytics() : super.disabled();

  static final selections = <({String type, int rank, int queryLength})>[];

  @override
  Future<void> trackSearchResultSelected({
    required String resultType,
    required int rank,
    required int queryLength,
  }) async {
    selections.add((type: resultType, rank: rank, queryLength: queryLength));
  }
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

final _defaultSources = [
  _source('s1', 'Mediapart', isTrusted: true),
  _source('s2', 'Le Monde', url: 'https://lemonde.fr'),
];

/// Catalogue vu par la sheet — réassignable par un test qui a besoin de plus
/// de matches (cap « voir tout »), remis à plat dans `setUp`.
List<Source> _sources = _defaultSources;

final _topics = [
  UserTopicProfile(id: 't1', name: 'Écologie', slugParent: 'environment'),
];

/// Hôte minimal : GoRouter (la sheet lit la route courante) + palette Facteur.
Widget _host({
  String initialLocation = RoutePaths.flaner,
  FeedFilterSelection selection = FeedFilterSelection.empty,
}) {
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
      feedFilterSelectionProvider.overrideWith((ref) => selection),
      userSourcesProvider.overrideWith(() => _StubCatalog(_sources)),
      userSourcesStateProvider.overrideWith(() => _StubSourcesState()),
      customTopicsProvider.overrideWith(() => _StubTopics(_topics)),
      trendingTopicsProvider.overrideWith((ref) async => <TrendingTopic>[]),
      analyticsServiceProvider.overrideWithValue(_RecordingAnalytics()),
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
    _RecordingFeedNotifier.applyGate = null;
    _RecordingAnalytics.selections.clear();
    _SheetHost.applied = 0;
    _sources = _defaultSources;
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
    expect(find.text('CHERCHER UNE SOURCE'), findsOneWidget);
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

    expect(find.text('CHERCHER UNE SOURCE'), findsOneWidget);
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
        .where((s) => s == 'ARTICLES' || s == 'CHERCHER UNE SOURCE')
        .toList();
    expect(headers.first, 'CHERCHER UNE SOURCE');
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

  testWidgets(
      'valider au clavier le nom exact d\'une source suivie sélectionne la source',
      (tester) async {
    await _openSheet(tester);
    await tester.enterText(find.byType(TextField), 'Mediapart');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(_RecordingFeedNotifier.calls, contains('source:s1'));
    expect(_RecordingFeedNotifier.calls, isNot(contains(startsWith('keyword:'))));
  });

  testWidgets(
      'valider au clavier le nom exact d\'un sujet suivi sélectionne le sujet',
      (tester) async {
    await _openSheet(tester);
    await tester.enterText(find.byType(TextField), 'Écologie');
    // Laisse `customTopicsProvider` se résoudre avant de soumettre — sans
    // frappe préalable il n'a encore jamais été lu par la sheet (contrairement
    // au catalogue de sources, déjà résolu pour le bloc « Tes sources »).
    await tester.pump(const Duration(milliseconds: 250));
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(_RecordingFeedNotifier.calls, contains('topic:environment'));
    expect(_RecordingFeedNotifier.calls, isNot(contains(startsWith('keyword:'))));
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

  testWidgets('sans filtre actif, pas de CTA « effacer »', (tester) async {
    await _openSheet(tester);
    expect(find.text('Effacer le filtre'), findsNothing);
  });

  testWidgets('« effacer le filtre » appelle clearFilters() (toute dimension)',
      (tester) async {
    // Gaté sur le filtre *réellement* actif (ici un filtre source, pas un
    // mot-clé) : depuis L'Essentiel la sheet est la seule sortie.
    await tester.pumpWidget(
      _host(selection: const FeedFilterSelection(sourceId: 's1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('OUVRIR'));
    await tester.pumpAndSettle();

    expect(find.text('Effacer le filtre'), findsOneWidget);
    await tester.tap(find.text('Effacer le filtre'));
    await tester.pumpAndSettle();

    expect(_RecordingFeedNotifier.calls, contains('clearFilters'));
    // Annuler n'est pas appliquer : `onApplied` navigue vers Flâner depuis
    // L'Essentiel, on ne doit pas téléporter l'utilisateur pour un « non ».
    expect(_SheetHost.applied, 0);
  });

  testWidgets('onApplied part AVANT que apply() ne se résolve', (tester) async {
    // L'ordre `pop → onApplied → await apply` fait démarrer la bascule
    // Essentiel → Flâner avant le refresh réseau (sinon écran figé).
    final gate = _RecordingFeedNotifier.applyGate = Completer<void>();
    await _openSheet(tester);
    await _type(tester, 'retraites');

    await tester.tap(find.text('Rechercher « retraites »'));
    await tester.pump(); // laisse pop + onApplied s'exécuter

    // onApplied a déjà notifié le hôte, mais apply() (setKeyword) est encore
    // suspendu sur le gate : aucun appel enregistré.
    expect(_SheetHost.applied, 1);
    expect(_RecordingFeedNotifier.calls, isEmpty);

    gate.complete();
    await tester.pumpAndSettle();
    expect(_RecordingFeedNotifier.calls, contains('keyword:retraites:false'));
  });

  testWidgets('le rang est global : la 2e section ne repart pas de 0',
      (tester) async {
    await _openSheet(tester);
    await _type(tester, 'retraites');

    // ARTICLES (rang 0) puis CHERCHER UNE SOURCE (rang 1).
    await tester.tap(find.text('Chercher « retraites » sur le web'));
    await tester.pumpAndSettle();

    expect(_RecordingAnalytics.selections.single.type, 'add_source');
    expect(_RecordingAnalytics.selections.single.rank, 1);
    expect(_RecordingAnalytics.selections.single.queryLength, 9);
  });

  testWidgets('un raccourci du cold start porte la longueur de sa requête',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'feed_search_history': ['retraites'],
    });
    await _openSheet(tester);

    expect(find.text('RECHERCHES RÉCENTES'), findsOneWidget);
    await tester.tap(find.text('retraites'));
    await tester.pumpAndSettle();

    // Le champ de saisie est vide ici : sans le libellé du chip, `query_length`
    // vaudrait 0 sur tout le cold start.
    expect(_RecordingAnalytics.selections.single.queryLength, 9);
  });

  testWidgets('« voir tout » déplie les résultats au-delà du cap de 3',
      (tester) async {
    _sources = [
      for (var i = 1; i <= 5; i++)
        _source('n$i', 'Nouvelle République $i', isTrusted: true),
    ];
    await _openSheet(tester);
    await _type(tester, 'nouvelle');

    expect(find.textContaining('Nouvelle République'), findsNWidgets(3));
    expect(find.text('Voir tout (5)'), findsOneWidget);

    await tester.tap(find.text('Voir tout (5)'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Nouvelle République'), findsNWidgets(5));
    expect(find.text('Voir moins'), findsOneWidget);
  });
}
