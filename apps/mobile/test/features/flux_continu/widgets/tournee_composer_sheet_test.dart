// PR « Composer ma Tournée » — couverture de la modale de composition :
// rendu MA TOURNÉE (thèmes + sources mélangés), trait « Hors Tournée du jour »
// au-delà du cap 5, et handlers ajout/retrait (membership) via spies.
import 'package:facteur/config/routes.dart';
import 'package:facteur/config/theme.dart';
import 'package:facteur/features/flux_continu/widgets/tournee_composer_sheet.dart';
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

UserInterestsState _interests(List<FavoriteRef> favorites) =>
    UserInterestsState(
      themes: const [],
      customTopics: const [],
      favorites: favorites,
      favoriteCount: favorites.length,
      favoriteCap: 5,
    );

UserSourcesState _sources({
  List<SourceFavoriteRef> favorites = const [],
  List<SourceInterest> followed = const [],
}) =>
    UserSourcesState(
      sources: [
        ...favorites.map((f) => SourceInterest(
              sourceId: f.sourceId,
              state: InterestState.favorite,
              priorityMultiplier: 1.0,
            )),
        ...followed,
      ],
      favorites: favorites,
      favoriteCount: favorites.length,
      favoriteCap: 5,
    );

Source _source(String id, String name) =>
    Source(id: id, name: name, type: SourceType.article);

Widget _wrap(Widget child) => MaterialApp(
      theme: ThemeData(extensions: [FacteurPalettes.light]),
      home: Scaffold(body: child),
    );

Future<({_SpyInterestsNotifier interests, _SpySourcesNotifier sources})>
    _openSheet(
  WidgetTester tester, {
  required UserInterestsState interests,
  required UserSourcesState sources,
  List<Source> catalog = const [],
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
      ],
      child: _wrap(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showTourneeComposerSheet(context),
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

/// Variante GoRouter — ouvre la sheet sous un `MaterialApp.router` avec des
/// routes nommées `sources` / `my-interests`, pour tester le footer GÉRER (pop
/// de la sheet + navigation `pushNamed`).
Future<void> _openSheetWithRouter(
  WidgetTester tester, {
  required UserInterestsState interests,
  required UserSourcesState sources,
}) async {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showTourneeComposerSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/settings/sources',
        name: RouteNames.sources,
        builder: (_, __) =>
            const Scaffold(body: Center(child: Text('SOURCES SCREEN'))),
      ),
      GoRoute(
        path: '/settings/interests',
        name: RouteNames.myInterests,
        builder: (_, __) =>
            const Scaffold(body: Center(child: Text('INTERESTS SCREEN'))),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userInterestsProvider.overrideWith(() => _SpyInterestsNotifier(interests)),
        userSourcesStateProvider.overrideWith(() => _SpySourcesNotifier(sources)),
        userSourcesProvider.overrideWith(() => _StubCatalogNotifier(const [])),
        veilleActiveConfigProvider.overrideWith(() => _StubVeilleNotifier()),
      ],
      child: MaterialApp.router(
        theme: ThemeData(extensions: [FacteurPalettes.light]),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('rend le titre + les sections MA TOURNÉE / AJOUTER', (
    tester,
  ) async {
    await _openSheet(
      tester,
      interests: _interests(const []),
      sources: _sources(),
    );

    expect(find.text('Composer ma Tournée'), findsOneWidget);
    expect(find.text('MA TOURNÉE'), findsOneWidget);
    expect(find.text('AJOUTER'), findsOneWidget);
    // Tournée vide → hint.
    expect(find.textContaining('Ta Tournée est vide'), findsOneWidget);
  });

  testWidgets('MA TOURNÉE mélange thèmes + sources favoris, sans trait ≤ 5', (
    tester,
  ) async {
    await _openSheet(
      tester,
      interests: _interests(const [
        ThemeFavoriteRef(slug: 'tech'),
        ThemeFavoriteRef(slug: 'science'),
      ]),
      sources: _sources(
        favorites: const [SourceFavoriteRef(sourceId: 's1', position: 0)],
      ),
      catalog: [_source('s1', 'Le Monde')],
    );

    expect(find.text('Technologie'), findsOneWidget);
    expect(find.text('Science'), findsOneWidget);
    expect(find.text('Le Monde'), findsOneWidget);
    expect(find.text('Hors Tournée du jour'), findsNothing);
  });

  testWidgets('affiche « Hors Tournée du jour » au-delà de 5 sections', (
    tester,
  ) async {
    await _openSheet(
      tester,
      interests: _interests(const [
        ThemeFavoriteRef(slug: 'tech'),
        ThemeFavoriteRef(slug: 'science'),
        ThemeFavoriteRef(slug: 'society'),
        ThemeFavoriteRef(slug: 'politics'),
        ThemeFavoriteRef(slug: 'environment'),
        ThemeFavoriteRef(slug: 'international'),
      ]),
      sources: _sources(),
    );

    expect(find.text('Hors Tournée du jour'), findsOneWidget);
  });

  testWidgets('retirer une source → setSourceState(.., followed)', (
    tester,
  ) async {
    final spies = await _openSheet(
      tester,
      interests: _interests(const []),
      sources: _sources(
        favorites: const [SourceFavoriteRef(sourceId: 's1', position: 0)],
      ),
      catalog: [_source('s1', 'Le Monde')],
    );

    await tester.tap(
      find.byIcon(PhosphorIcons.minusCircle(PhosphorIconsStyle.fill)),
    );
    await tester.pumpAndSettle();

    expect(spies.sources.stateCalls, [('s1', InterestState.followed)]);
  });

  testWidgets('ajouter un thème → setInterestState(.., favorite)', (
    tester,
  ) async {
    final spies = await _openSheet(
      tester,
      interests: _interests(const []),
      sources: _sources(),
    );

    // Onglet « Thèmes » de la zone AJOUTER.
    await tester.tap(find.text('Thèmes'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Technologie'));
    await tester.pumpAndSettle();

    expect(spies.interests.stateCalls.length, 1);
    final (ref, state) = spies.interests.stateCalls.single;
    expect(ref, isA<ThemeFavoriteRef>());
    expect((ref as ThemeFavoriteRef).slug, 'tech');
    expect(state, InterestState.favorite);
  });

  group('footer GÉRER', () {
    testWidgets('rend 2 ChoiceTile, « Gérer ses sources » en premier', (
      tester,
    ) async {
      await _openSheet(
        tester,
        interests: _interests(const []),
        sources: _sources(),
      );

      expect(find.text('GÉRER'), findsOneWidget);
      expect(find.text('Gérer ses sources'), findsOneWidget);
      expect(find.text('Gérer ses intérêts'), findsOneWidget);

      // Sources mises en avant → au-dessus des intérêts.
      final sourcesY = tester.getTopLeft(find.text('Gérer ses sources')).dy;
      final interetsY = tester.getTopLeft(find.text('Gérer ses intérêts')).dy;
      expect(sourcesY, lessThan(interetsY));
    });

    testWidgets('tap « Gérer ses sources » → ferme la sheet + route sources', (
      tester,
    ) async {
      await _openSheetWithRouter(
        tester,
        interests: _interests(const []),
        sources: _sources(),
      );
      expect(find.text('Composer ma Tournée'), findsOneWidget);

      await tester.ensureVisible(find.text('Gérer ses sources'));
      await tester.tap(find.text('Gérer ses sources'));
      await tester.pumpAndSettle();

      // Sheet fermée (pop) + navigation effectuée.
      expect(find.text('Composer ma Tournée'), findsNothing);
      expect(find.text('SOURCES SCREEN'), findsOneWidget);
    });

    testWidgets('tap « Gérer ses intérêts » → ferme la sheet + route intérêts', (
      tester,
    ) async {
      await _openSheetWithRouter(
        tester,
        interests: _interests(const []),
        sources: _sources(),
      );

      await tester.ensureVisible(find.text('Gérer ses intérêts'));
      await tester.tap(find.text('Gérer ses intérêts'));
      await tester.pumpAndSettle();

      expect(find.text('Composer ma Tournée'), findsNothing);
      expect(find.text('INTERESTS SCREEN'), findsOneWidget);
    });
  });

  group('markCustomized — 1ʳᵉ mutation', () {
    testWidgets('retirer une source marque la Tournée comme customisée', (
      tester,
    ) async {
      await _openSheet(
        tester,
        interests: _interests(const []),
        sources: _sources(
          favorites: const [SourceFavoriteRef(sourceId: 's1', position: 0)],
        ),
        catalog: [_source('s1', 'Le Monde')],
      );

      await tester.tap(
        find.byIcon(PhosphorIcons.minusCircle(PhosphorIconsStyle.fill)),
      );
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('tournee_customized_v1'), isTrue);
    });

    testWidgets('ajouter un thème marque la Tournée comme customisée', (
      tester,
    ) async {
      await _openSheet(
        tester,
        interests: _interests(const []),
        sources: _sources(),
      );

      await tester.tap(find.text('Thèmes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Technologie'));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('tournee_customized_v1'), isTrue);
    });
  });
}
