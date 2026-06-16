// Story 10.2 — sheet unifiée « Mes favoris » : deux sections (Essentiel /
// Flâner), appartenance exclusive des sources (la clé `source:` dans
// `tournee_order_v1` ⇒ Essentiel, sinon Flâner), déplacement de mode, funnel
// veille sur les sujets, et caps 7/10 par section.
import 'package:facteur/config/routes.dart';
import 'package:facteur/config/theme.dart';
import 'package:facteur/features/digest/providers/serein_toggle_provider.dart';
import 'package:facteur/features/flux_continu/providers/tournee_smart_arrangement_provider.dart';
import 'package:facteur/features/flux_continu/widgets/manage_favorites_sheet.dart';
import 'package:facteur/features/grille/models/grille_models.dart';
import 'package:facteur/features/grille/providers/grille_provider.dart';
import 'package:facteur/features/grille/repositories/grille_repository.dart';
import 'package:facteur/features/my_interests/models/user_interests_state.dart';
import 'package:facteur/features/my_interests/models/user_sources_state.dart';
import 'package:facteur/features/my_interests/providers/user_interests_provider.dart';
import 'package:facteur/features/my_interests/providers/user_sources_state_provider.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/features/sources/providers/sources_providers.dart';
import 'package:facteur/features/veille/models/veille_config_dto.dart';
import 'package:facteur/features/veille/providers/veille_active_config_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SpyInterestsNotifier extends UserInterestsNotifier {
  _SpyInterestsNotifier(this._initial);
  final UserInterestsState _initial;
  final List<(FavoriteRef, InterestState)> stateCalls = [];

  @override
  Future<UserInterestsState> build() async => _initial;

  @override
  Future<void> setInterestState(FavoriteRef ref, InterestState s) async {
    stateCalls.add((ref, s));
  }

  @override
  Future<void> reorderFavorites(List<FavoriteRef> ordered) async {}
}

class _SpySourcesNotifier extends UserSourcesStateNotifier {
  _SpySourcesNotifier(this._initial);
  final UserSourcesState _initial;
  final List<(String, InterestState)> stateCalls = [];

  @override
  Future<UserSourcesState> build() async => _initial;

  @override
  Future<void> setSourceState(String sourceId, InterestState s) async {
    stateCalls.add((sourceId, s));
  }

  @override
  Future<void> reorderFavorites(List<SourceFavoriteRef> ordered) async {}
}

class _StubCatalogNotifier extends UserSourcesNotifier {
  _StubCatalogNotifier(this._initial);
  final List<Source> _initial;

  @override
  Future<List<Source>> build() async => _initial;
}

class _StubVeilleNotifier extends VeilleActiveConfigNotifier {
  @override
  Future<VeilleConfigDto?> build() async => null;
}

class _FakeGrilleRepository implements GrilleRepository {
  _FakeGrilleRepository(this.today);
  final GrilleTodayResponse? today;

  @override
  Future<GrilleTodayResponse> getToday() async {
    final value = today;
    if (value == null) throw Exception('mock: no grille');
    return value;
  }

  @override
  Future<GrilleLeaderboardResponse> getLeaderboard() =>
      throw UnimplementedError();

  @override
  Future<GrilleRevealResponse> revealWord() => throw UnimplementedError();

  @override
  Future<GrilleGuessResponse> submitGuess(String mot) =>
      throw UnimplementedError();
}

class _StubSereinToggleNotifier extends SereinToggleNotifier {
  _StubSereinToggleNotifier(super.ref, bool enabled) {
    state = SereinToggleState(enabled: enabled, isLoading: false);
  }
}

UserInterestsState _interests({
  List<FavoriteRef> favorites = const [],
  List<CustomTopicInterest> customTopics = const [],
}) =>
    UserInterestsState(
      themes: const [],
      customTopics: customTopics,
      favorites: favorites,
      favoriteCount: favorites.length,
      favoriteCap: 7,
    );

UserSourcesState _sources({
  List<SourceFavoriteRef> favorites = const [],
  List<SourceInterest> followed = const [],
}) =>
    UserSourcesState(
      sources: [
        ...favorites.map(
          (f) => SourceInterest(
            sourceId: f.sourceId,
            state: InterestState.favorite,
            priorityMultiplier: 1.0,
          ),
        ),
        ...followed,
      ],
      favorites: favorites,
      favoriteCount: favorites.length,
      favoriteCap: 7,
    );

CustomTopicInterest _topic(String id, String name,
        {String slugParent = 'tech'}) =>
    CustomTopicInterest(
      id: id,
      topicName: name,
      slugParent: slugParent,
      state: InterestState.favorite,
      priorityMultiplier: 2.0,
    );

Source _source(String id, String name) =>
    Source(id: id, name: name, type: SourceType.article);

Widget _wrap(Widget child) => MaterialApp(
      theme: ThemeData(
        extensions: [FacteurPalettes.light],
        splashFactory: NoSplash.splashFactory,
      ),
      home: Scaffold(body: child),
    );

Future<({_SpyInterestsNotifier interests, _SpySourcesNotifier sources})>
    _openSheet(
  WidgetTester tester, {
  required UserInterestsState interests,
  required UserSourcesState sources,
  List<Source> catalog = const [],
  ManageFavoritesEntry entry = ManageFavoritesEntry.essentiel,
}) async {
  final spyInterests = _SpyInterestsNotifier(interests);
  final spySources = _SpySourcesNotifier(sources);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userInterestsProvider.overrideWith(() => spyInterests),
        userSourcesStateProvider.overrideWith(() => spySources),
        userSourcesProvider.overrideWith(() => _StubCatalogNotifier(catalog)),
        veilleActiveConfigProvider.overrideWith(() => _StubVeilleNotifier()),
        grilleRepositoryProvider.overrideWithValue(
          _FakeGrilleRepository(null),
        ),
        sereinToggleProvider.overrideWith(
          (ref) => _StubSereinToggleNotifier(ref, false),
        ),
        tourneeSmartArrangementProvider.overrideWith(
          (ref) => TourneeSmartArrangementNotifier(ref),
        ),
      ],
      child: _wrap(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showManageFavoritesSheet(context, entry: entry),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return (interests: spyInterests, sources: spySources);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('rend le titre + les deux sections + AJOUTER + GÉRER',
      (tester) async {
    await _openSheet(
      tester,
      interests: _interests(),
      sources: _sources(),
    );

    expect(find.text('Mes favoris'), findsOneWidget);
    expect(find.text('BLOCS DE TA PAGE L\'ESSENTIEL'), findsOneWidget);
    expect(find.text('ONGLETS DE TA PAGE FLÂNER'), findsOneWidget);
    expect(find.text('AJOUTER'), findsOneWidget);
    expect(find.text('GÉRER'), findsOneWidget);
    // Éditorial visible par défaut dans l'Essentiel. « Actus & Mot du jour »
    // = Actus + Grille implicitement rattachée (Grille plus draggable).
    expect(find.text('Actus & Mot du jour'), findsOneWidget);
    expect(find.text('Bonnes Nouvelles'), findsOneWidget);
    // La Grille n'est plus un bloc drag&drop autonome.
    expect(find.text('La Grille du jour'), findsNothing);
    // 3 segments d'ajout.
    expect(find.text('Sources'), findsOneWidget);
    expect(find.text('Thèmes'), findsOneWidget);
    expect(find.text('Sujets'), findsOneWidget);
  });

  testWidgets(
      'source en mode Essentiel (clé dans tournee_order) apparaît sous '
      'l\'Essentiel, pas sous Flâner', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'tournee_order_v1': ['source:s1'],
    });
    await _openSheet(
      tester,
      interests: _interests(),
      sources: _sources(
        favorites: const [SourceFavoriteRef(sourceId: 's1', position: 0)],
      ),
      catalog: [_source('s1', 'Le Monde')],
    );

    expect(find.text('Le Monde'), findsOneWidget);
    final sourceY = tester.getTopLeft(find.text('Le Monde')).dy;
    final essentielY =
        tester.getTopLeft(find.text('BLOCS DE TA PAGE L\'ESSENTIEL')).dy;
    final flanerY =
        tester.getTopLeft(find.text('ONGLETS DE TA PAGE FLÂNER')).dy;
    expect(sourceY, greaterThan(essentielY));
    expect(sourceY, lessThan(flanerY));
  });

  testWidgets(
      'source sans clé tournee_order apparaît sous Flâner (mode par défaut)',
      (tester) async {
    await _openSheet(
      tester,
      interests: _interests(),
      sources: _sources(
        favorites: const [SourceFavoriteRef(sourceId: 's1', position: 0)],
      ),
      catalog: [_source('s1', 'Le Monde')],
    );

    final sourceY = tester.getTopLeft(find.text('Le Monde')).dy;
    final flanerY =
        tester.getTopLeft(find.text('ONGLETS DE TA PAGE FLÂNER')).dy;
    expect(sourceY, greaterThan(flanerY));
  });

  testWidgets('déplacer une source Essentiel → Flâner met à jour les 2 prefs',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'tournee_order_v1': ['source:s1'],
    });
    await _openSheet(
      tester,
      interests: _interests(),
      sources: _sources(
        favorites: const [SourceFavoriteRef(sourceId: 's1', position: 0)],
      ),
      catalog: [_source('s1', 'Le Monde')],
    );

    await tester.tap(
      find.byIcon(PhosphorIcons.arrowLineDown(PhosphorIconsStyle.bold)),
    );
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getStringList('tournee_order_v1') ?? const <String>[],
      isNot(contains('source:s1')),
    );
    expect(prefs.getStringList('pinned_tabs_order_v1'), contains('source:s1'));
    expect(prefs.getBool('tournee_customized_v1'), isTrue);
  });

  testWidgets('déplacer une source Flâner → Essentiel ajoute la clé tournee',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pinned_tabs_order_v1': ['source:s1'],
    });
    await _openSheet(
      tester,
      interests: _interests(),
      sources: _sources(
        favorites: const [SourceFavoriteRef(sourceId: 's1', position: 0)],
      ),
      catalog: [_source('s1', 'Le Monde')],
    );

    await tester.tap(
      find.byIcon(PhosphorIcons.arrowLineUp(PhosphorIconsStyle.bold)),
    );
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('tournee_order_v1'), contains('source:s1'));
    expect(
      prefs.getStringList('pinned_tabs_order_v1') ?? const <String>[],
      isNot(contains('source:s1')),
    );
  });

  testWidgets('ajouter un thème → setInterestState(favorite) + clé tournee',
      (tester) async {
    final spies = await _openSheet(
      tester,
      interests: _interests(),
      sources: _sources(),
    );

    await tester.ensureVisible(find.text('Thèmes'));
    await tester.tap(find.text('Thèmes'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Technologie'));
    await tester.tap(find.text('Technologie'));
    await tester.pumpAndSettle();

    expect(spies.interests.stateCalls.length, 1);
    final (ref, state) = spies.interests.stateCalls.single;
    expect((ref as ThemeFavoriteRef).slug, 'tech');
    expect(state, InterestState.favorite);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('tournee_order_v1'), contains('theme:tech'));
    expect(prefs.getBool('tournee_customized_v1'), isTrue);
  });

  testWidgets(
      '« Hors Tournée du jour (7) » apparaît au-delà de 7 sections Essentiel',
      (tester) async {
    await _openSheet(
      tester,
      interests: _interests(favorites: const [
        ThemeFavoriteRef(slug: 'tech'),
        ThemeFavoriteRef(slug: 'science'),
        ThemeFavoriteRef(slug: 'society'),
        ThemeFavoriteRef(slug: 'politics'),
        ThemeFavoriteRef(slug: 'environment'),
        ThemeFavoriteRef(slug: 'international'),
        ThemeFavoriteRef(slug: 'economy'),
        ThemeFavoriteRef(slug: 'culture'),
      ]),
      sources: _sources(),
    );

    // Le cap (élargi 5 → 7) est explicité entre parenthèses.
    expect(find.text('Hors Tournée du jour (7)'), findsOneWidget);
    // Le compteur de l'en-tête reflète aussi le cap.
    expect(find.text('· 7/7'), findsOneWidget);
  });

  testWidgets(
      'déplacer un thème Essentiel → Flâner retire la clé tournee et ajoute '
      'la clé tab', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'tournee_order_v1': ['theme:tech'],
    });
    await _openSheet(
      tester,
      interests: _interests(favorites: const [ThemeFavoriteRef(slug: 'tech')]),
      sources: _sources(),
    );

    // Le thème est sous l'Essentiel ; bouton « déplacer vers Flâner ».
    expect(find.text('Technologie'), findsOneWidget);
    await tester.tap(
      find.byIcon(PhosphorIcons.arrowLineDown(PhosphorIconsStyle.bold)),
    );
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getStringList('tournee_order_v1') ?? const <String>[],
      isNot(contains('theme:tech')),
    );
    expect(prefs.getStringList('pinned_tabs_order_v1'), contains('theme:tech'));
    expect(prefs.getBool('tournee_customized_v1'), isTrue);
  });

  testWidgets(
      'un thème avec clé tab (Flâner) est listé sous Flâner, déplaçable vers '
      'l\'Essentiel', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pinned_tabs_order_v1': ['theme:tech'],
    });
    await _openSheet(
      tester,
      interests: _interests(favorites: const [ThemeFavoriteRef(slug: 'tech')]),
      sources: _sources(),
    );

    final themeY = tester.getTopLeft(find.text('Technologie')).dy;
    final flanerY =
        tester.getTopLeft(find.text('ONGLETS DE TA PAGE FLÂNER')).dy;
    expect(themeY, greaterThan(flanerY));

    await tester.tap(
      find.byIcon(PhosphorIcons.arrowLineUp(PhosphorIconsStyle.bold)),
    );
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('tournee_order_v1'), contains('theme:tech'));
    expect(
      prefs.getStringList('pinned_tabs_order_v1') ?? const <String>[],
      isNot(contains('theme:tech')),
    );
  });

  testWidgets('un sujet favori est listé sous Flâner avec le funnel 🔭',
      (tester) async {
    await _openSheet(
      tester,
      interests: _interests(
        favorites: const [CustomTopicFavoriteRef(id: 't1')],
        customTopics: [_topic('t1', 'Climat', slugParent: 'environment')],
      ),
      sources: _sources(),
    );

    expect(find.text('Climat'), findsOneWidget);
    final climatY = tester.getTopLeft(find.text('Climat')).dy;
    final flanerY =
        tester.getTopLeft(find.text('ONGLETS DE TA PAGE FLÂNER')).dy;
    expect(climatY, greaterThan(flanerY));
    // Affordance veille présente sur la ligne sujet.
    expect(
      find.byIcon(PhosphorIcons.binoculars(PhosphorIconsStyle.regular)),
      findsWidgets,
    );
  });

  testWidgets('🔭 sur un sujet ouvre la config veille (pop + route)',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showManageFavoritesSheet(
                  context,
                  entry: ManageFavoritesEntry.flaner,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/veille/config',
          name: RouteNames.veilleConfig,
          builder: (_, __) =>
              const Scaffold(body: Center(child: Text('VEILLE CONFIG'))),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userInterestsProvider.overrideWith(
            () => _SpyInterestsNotifier(
              _interests(
                favorites: const [CustomTopicFavoriteRef(id: 't1')],
                customTopics: [_topic('t1', 'Climat')],
              ),
            ),
          ),
          userSourcesStateProvider.overrideWith(
            () => _SpySourcesNotifier(_sources()),
          ),
          userSourcesProvider
              .overrideWith(() => _StubCatalogNotifier(const [])),
          veilleActiveConfigProvider.overrideWith(() => _StubVeilleNotifier()),
          grilleRepositoryProvider.overrideWithValue(
            _FakeGrilleRepository(null),
          ),
          sereinToggleProvider.overrideWith(
            (ref) => _StubSereinToggleNotifier(ref, false),
          ),
        tourneeSmartArrangementProvider.overrideWith(
          (ref) => TourneeSmartArrangementNotifier(ref),
        ),
        ],
        child: MaterialApp.router(
          theme: ThemeData(
            extensions: [FacteurPalettes.light],
            splashFactory: NoSplash.splashFactory,
          ),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byIcon(PhosphorIcons.binoculars(PhosphorIconsStyle.regular)).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Mes favoris'), findsNothing);
    expect(find.text('VEILLE CONFIG'), findsOneWidget);
  });
}
