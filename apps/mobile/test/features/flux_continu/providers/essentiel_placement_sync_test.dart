/// Tests du réconciliateur de placement Essentiel/Flâner
/// ([reconcileEssentielPlacement]).
///
/// Couvre les deux moitiés du fix :
///  - **Backfill local → DB** : un favori dont le backend ignore le placement
///    (`essentiel_mode == null`) fait remonter le placement *local* du device
///    en un PATCH (une fois, gardé par le flag prefs).
///  - **Hydratation DB → local** : un favori dont le backend connaît le
///    placement restaure les prefs locales — c'est ce qui répare la perte à la
///    réinstallation.
library;

import 'package:facteur/features/feed/providers/tab_order_prefs_provider.dart';
import 'package:facteur/features/flux_continu/providers/essentiel_placement_sync.dart';
import 'package:facteur/features/flux_continu/providers/tournee_order_prefs_provider.dart';
import 'package:facteur/features/my_interests/models/user_interests_state.dart';
import 'package:facteur/features/my_interests/models/user_sources_state.dart';
import 'package:facteur/features/my_interests/repositories/user_interests_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Repo fake : sert des états contrôlés et enregistre les PATCH émis.
class _FakeRepo implements UserInterestsRepository {
  UserSourcesState sources;
  UserInterestsState interests;

  final List<({String sourceId, bool? mode})> sourcePatches = [];
  final List<({String slug, bool? mode})> themePatches = [];

  _FakeRepo({required this.sources, required this.interests});

  @override
  Future<UserSourcesState> fetchSourcesState() async => sources;

  @override
  Future<UserInterestsState> fetchInterests() async => interests;

  @override
  Future<UserSourcesState> setSourceState({
    required String sourceId,
    required InterestState state,
    int? position,
    bool? essentielMode,
  }) async {
    sourcePatches.add((sourceId: sourceId, mode: essentielMode));
    return sources;
  }

  @override
  Future<UserInterestsState> setInterestState({
    required FavoriteRef ref,
    required InterestState state,
    int? position,
    bool? essentielMode,
  }) async {
    if (ref is ThemeFavoriteRef) {
      themePatches.add((slug: ref.slug, mode: essentielMode));
    }
    return interests;
  }

  @override
  Future<UserSourcesState> reorderSourceFavorites(
          List<SourceFavoriteRef> ordered) async =>
      sources;

  @override
  Future<UserInterestsState> reorderFavorites(
          List<FavoriteRef> ordered) async =>
      interests;
}

/// Probe : expose [reconcileEssentielPlacement] comme un provider awaitable
/// (la fonction prend un `Ref`, indisponible directement depuis un container).
final _reconcileProbe =
    FutureProvider<void>((ref) => reconcileEssentielPlacement(ref));

UserSourcesState _sourcesWith(List<SourceInterest> items) => UserSourcesState(
      sources: items,
      favorites: [
        for (var i = 0; i < items.length; i++)
          if (items[i].state == InterestState.favorite)
            SourceFavoriteRef(sourceId: items[i].sourceId, position: i),
      ],
      favoriteCount: items.where((s) => s.state == InterestState.favorite).length,
      favoriteCap: 5,
    );

UserInterestsState _interestsWith(List<ThemeInterest> themes) =>
    UserInterestsState(
      themes: themes,
      customTopics: const [],
      favorites: [
        for (final t in themes)
          if (t.state == InterestState.favorite)
            ThemeFavoriteRef(slug: t.interestSlug),
      ],
      favoriteCount: themes.where((t) => t.state == InterestState.favorite).length,
      favoriteCap: 5,
    );

Future<ProviderContainer> _boot(
  _FakeRepo repo,
  Map<String, Object> prefs,
) async {
  SharedPreferences.setMockInitialValues(prefs);
  final container = ProviderContainer(overrides: [
    userInterestsRepositoryProvider.overrideWithValue(repo),
  ]);
  // Réchauffe les StateNotifier prefs (chargement async depuis SharedPreferences)
  // avant la réconciliation qui lit leur état en synchrone.
  container.read(tourneeOrderPrefsProvider);
  container.read(tabOrderPrefsProvider);
  await Future<void>.delayed(const Duration(milliseconds: 20));
  return container;
}

void main() {
  const s1 = 'S1';

  test('backfill: source Essentiel locale + backend null → PATCH essentiel=true',
      () async {
    final repo = _FakeRepo(
      sources: _sourcesWith(const [
        SourceInterest(
          sourceId: s1,
          state: InterestState.favorite,
          priorityMultiplier: 1.0,
          // essentielMode == null → candidat backfill.
        ),
      ]),
      interests: _interestsWith(const []),
    );
    // Le device place S1 dans l'Essentiel (clé dans tournee_order_v1).
    final container = await _boot(repo, {
      'tournee_order_v1': <String>['source:$s1'],
    });
    addTearDown(container.dispose);

    await container.read(_reconcileProbe.future);

    expect(repo.sourcePatches, hasLength(1));
    expect(repo.sourcePatches.single.sourceId, s1);
    expect(repo.sourcePatches.single.mode, isTrue);
    // Flag one-shot posé après un backfill réussi.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('essentiel_placement_reconciled_v1'), isTrue);
  });

  test(
      'backfill: source Flâner locale + backend null → PATCH essentiel=false',
      () async {
    final repo = _FakeRepo(
      sources: _sourcesWith(const [
        SourceInterest(
          sourceId: s1,
          state: InterestState.favorite,
          priorityMultiplier: 1.0,
        ),
      ]),
      interests: _interestsWith(const []),
    );
    // S1 en Flâner (clé dans pinned_tabs_order_v1, absente de tournee_order_v1).
    final container = await _boot(repo, {
      'pinned_tabs_order_v1': <String>['source:$s1'],
    });
    addTearDown(container.dispose);

    await container.read(_reconcileProbe.future);

    expect(repo.sourcePatches.single.mode, isFalse);
  });

  test('backfill ne se rejoue pas si le flag est déjà posé', () async {
    final repo = _FakeRepo(
      sources: _sourcesWith(const [
        SourceInterest(
          sourceId: s1,
          state: InterestState.favorite,
          priorityMultiplier: 1.0,
        ),
      ]),
      interests: _interestsWith(const []),
    );
    final container = await _boot(repo, {
      'tournee_order_v1': <String>['source:$s1'],
      'essentiel_placement_reconciled_v1': true,
    });
    addTearDown(container.dispose);

    await container.read(_reconcileProbe.future);

    expect(repo.sourcePatches, isEmpty);
  });

  test(
      'hydrate: source backend essentiel=true + prefs vides → clé ré-ajoutée '
      'à tournee_order (répro du bug réinstallation)', () async {
    final repo = _FakeRepo(
      sources: _sourcesWith(const [
        SourceInterest(
          sourceId: s1,
          state: InterestState.favorite,
          priorityMultiplier: 1.0,
          essentielMode: true, // placement connu en DB.
        ),
      ]),
      interests: _interestsWith(const []),
    );
    // Device fraîchement réinstallé : aucune pref locale.
    final container = await _boot(repo, <String, Object>{});
    addTearDown(container.dispose);

    await container.read(_reconcileProbe.future);

    // L'Essentiel est restauré localement.
    expect(
      container.read(tourneeOrderPrefsProvider).order,
      contains('source:$s1'),
    );
    // Rien à backfiller (placement déjà connu) → aucun PATCH source.
    expect(repo.sourcePatches, isEmpty);
  });

  test(
      'hydrate: source backend essentiel=false → clé retirée de tournee, '
      'ajoutée à pinned_tabs', () async {
    final repo = _FakeRepo(
      sources: _sourcesWith(const [
        SourceInterest(
          sourceId: s1,
          state: InterestState.favorite,
          priorityMultiplier: 1.0,
          essentielMode: false,
        ),
      ]),
      interests: _interestsWith(const []),
    );
    // Localement (à tort) placé dans l'Essentiel : l'hydratation doit corriger.
    final container = await _boot(repo, {
      'tournee_order_v1': <String>['source:$s1'],
    });
    addTearDown(container.dispose);

    await container.read(_reconcileProbe.future);

    expect(
      container.read(tourneeOrderPrefsProvider).order,
      isNot(contains('source:$s1')),
    );
    expect(
      container.read(tabOrderPrefsProvider),
      contains('source:$s1'),
    );
  });

  test('hydrate: thème backend essentiel=true → clé retirée de pinned_tabs',
      () async {
    final repo = _FakeRepo(
      sources: _sourcesWith(const []),
      interests: _interestsWith(const [
        ThemeInterest(
          interestSlug: 'tech',
          weight: 1.0,
          state: InterestState.favorite,
          essentielMode: true,
        ),
      ]),
    );
    // Le thème était (à tort) en Flâner localement.
    final container = await _boot(repo, {
      'pinned_tabs_order_v1': <String>['theme:tech'],
    });
    addTearDown(container.dispose);

    await container.read(_reconcileProbe.future);

    // Essentiel = défaut du thème : il suffit qu'il quitte Flâner.
    expect(
      container.read(tabOrderPrefsProvider),
      isNot(contains('theme:tech')),
    );
  });
}
