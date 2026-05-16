/// Story 22.1 PR 3/3 — tests du sync one-shot des préférences `theme_priority_*`
/// vers les favoris backend.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:facteur/features/my_interests/models/user_interests_state.dart';
import 'package:facteur/features/my_interests/models/user_sources_state.dart';
import 'package:facteur/features/my_interests/repositories/user_interests_repository.dart';
import 'package:facteur/features/my_interests/services/interests_sync_service.dart';

class _RecorderRepo implements UserInterestsRepository {
  final List<(FavoriteRef, InterestState)> calls = [];
  Object? throwOnSet;

  @override
  Future<UserInterestsState> fetchInterests() async =>
      throw UnimplementedError();

  @override
  Future<UserInterestsState> setInterestState({
    required FavoriteRef ref,
    required InterestState state,
    int? position,
  }) async {
    calls.add((ref, state));
    if (throwOnSet != null) throw throwOnSet!;
    return const UserInterestsState(
      themes: [],
      customTopics: [],
      favorites: [],
      favoriteCount: 0,
      favoriteCap: 3,
    );
  }

  @override
  Future<UserInterestsState> reorderFavorites(List<FavoriteRef> ordered) async =>
      throw UnimplementedError();

  @override
  Future<UserSourcesState> fetchSourcesState() async =>
      throw UnimplementedError();

  @override
  Future<UserSourcesState> setSourceState({
    required String sourceId,
    required InterestState state,
    int? position,
  }) async =>
      throw UnimplementedError();

  @override
  Future<UserSourcesState> reorderSourceFavorites(
          List<SourceFavoriteRef> ordered) async =>
      throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<InterestsSyncService> makeService(_RecorderRepo repo) async {
    return InterestsSyncService(
      repository: repo,
      prefsFactory: SharedPreferences.getInstance,
    );
  }

  test('promeut chaque Thème legacy à multiplier >= 2.0 en favori', () async {
    SharedPreferences.setMockInitialValues({
      'theme_priority_Technologie': 2.0,
      'theme_priority_Sciences': 3.0,
      'theme_priority_Politique': 1.0, // ignoré : < 2.0
    });
    final repo = _RecorderRepo();
    final service = await makeService(repo);

    await service.syncLegacyThemePreferences();

    expect(repo.calls.length, 2);
    final promotedSlugs = repo.calls
        .map((c) => (c.$1 as ThemeFavoriteRef).slug)
        .toSet();
    expect(promotedSlugs, {'tech', 'science'});
    expect(repo.calls.every((c) => c.$2 == InterestState.favorite), isTrue);
  });

  test('est idempotent — 2e appel skip si flag déjà set', () async {
    SharedPreferences.setMockInitialValues({
      'theme_priority_Technologie': 2.0,
    });
    final repo = _RecorderRepo();
    final service = await makeService(repo);

    await service.syncLegacyThemePreferences();
    expect(repo.calls.length, 1);

    // Second run : flag posé, prefs purgées, mais même si on remettait des
    // prefs, le flag empêcherait toute mutation.
    SharedPreferences.setMockInitialValues({
      'interests_v2_legacy_synced': true,
      'theme_priority_Sciences': 3.0,
    });
    final repo2 = _RecorderRepo();
    final service2 = await makeService(repo2);
    await service2.syncLegacyThemePreferences();

    expect(repo2.calls, isEmpty);
  });

  test(
      'absorbe silencieusement FavoriteCapReachedException et continue le sync',
      () async {
    SharedPreferences.setMockInitialValues({
      'theme_priority_Technologie': 2.0,
      'theme_priority_Sciences': 2.0,
    });
    final repo = _RecorderRepo()..throwOnSet = const FavoriteCapReachedException(3);
    final service = await makeService(repo);

    // Ne doit pas crash, et le flag doit être posé in fine.
    await service.syncLegacyThemePreferences();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('interests_v2_legacy_synced'), isTrue);
    // Les 2 thèmes ont été essayés (le cap échoue silencieusement, on continue).
    expect(repo.calls.length, 2);
  });

  test('purge toutes les clés theme_priority_* après le sync', () async {
    SharedPreferences.setMockInitialValues({
      'theme_priority_Technologie': 2.0,
      'theme_priority_Sciences': 1.0,
      'theme_priority_Sport': 3.0,
      'other_key_preserved': 'keep_me',
    });
    final repo = _RecorderRepo();
    final service = await makeService(repo);

    await service.syncLegacyThemePreferences();

    final prefs = await SharedPreferences.getInstance();
    final remainingLegacy = prefs
        .getKeys()
        .where((k) => k.startsWith('theme_priority_'))
        .toList();
    expect(remainingLegacy, isEmpty);
    expect(prefs.getString('other_key_preserved'), 'keep_me');
    expect(prefs.getBool('interests_v2_legacy_synced'), isTrue);
  });

  test('ignore les clés au macro-label inconnu sans planter', () async {
    SharedPreferences.setMockInitialValues({
      'theme_priority_UnknownLabel': 2.0,
      'theme_priority_Technologie': 2.0,
    });
    final repo = _RecorderRepo();
    final service = await makeService(repo);

    await service.syncLegacyThemePreferences();

    expect(repo.calls.length, 1);
    expect((repo.calls.single.$1 as ThemeFavoriteRef).slug, 'tech');

    // La clé UnknownLabel est tout de même purgée (préfixe legacy).
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where((k) => k.startsWith('theme_priority_')),
        isEmpty);
  });
}
