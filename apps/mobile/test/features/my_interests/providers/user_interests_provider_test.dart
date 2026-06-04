/// Story 22.1 — tests du provider userInterestsProvider :
/// - optimistic update sur setInterestState
/// - rollback sur FavoriteCapReachedException
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/my_interests/models/user_interests_state.dart';
import 'package:facteur/features/my_interests/providers/user_interests_provider.dart';
import 'package:facteur/features/my_interests/repositories/user_interests_repository.dart';
import 'package:facteur/features/my_interests/models/user_sources_state.dart';

class _FakeRepo implements UserInterestsRepository {
  final UserInterestsState initial;
  int setCalls = 0;
  bool throwCap = false;
  Object? throwAfterOptimistic;

  _FakeRepo(this.initial);

  @override
  Future<UserInterestsState> fetchInterests() async => initial;

  @override
  Future<UserInterestsState> setInterestState({
    required FavoriteRef ref,
    required InterestState state,
    int? position,
  }) async {
    setCalls++;
    if (throwCap) throw const FavoriteCapReachedException(5);
    if (throwAfterOptimistic != null) throw throwAfterOptimistic!;
    final favorites = state == InterestState.favorite
        ? <FavoriteRef>[...initial.favorites, ref]
        : initial.favorites.where((f) => f != ref).toList();
    return initial.copyWith(
      favorites: favorites,
      favoriteCount: favorites.length,
    );
  }

  @override
  Future<UserInterestsState> reorderFavorites(
          List<FavoriteRef> ordered) async =>
      initial.copyWith(favorites: ordered);

  // Stubs unused for these tests.
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
  UserInterestsState seed() => const UserInterestsState(
        themes: [
          ThemeInterest(
            interestSlug: 'tech',
            weight: 1.0,
            state: InterestState.followed,
          ),
        ],
        customTopics: [],
        favorites: [],
        favoriteCount: 0,
        favoriteCap: 5,
      );

  test('optimistic update reflects new state before API resolves', () async {
    final repo = _FakeRepo(seed());
    final container = ProviderContainer(overrides: [
      userInterestsRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);

    final initial = await container.read(userInterestsProvider.future);
    expect(initial.favorites, isEmpty);

    // Schedule the mutation (don't await yet) and read state immediately —
    // the optimistic value should already be reflected.
    final pending = container
        .read(userInterestsProvider.notifier)
        .setInterestState(
            const ThemeFavoriteRef(slug: 'tech'), InterestState.favorite);

    final optimistic = container.read(userInterestsProvider).value!;
    expect(
        optimistic.favorites, contains(const ThemeFavoriteRef(slug: 'tech')));
    expect(optimistic.favoriteCount, 1);

    await pending;
    final settled = container.read(userInterestsProvider).value!;
    expect(settled.favorites, contains(const ThemeFavoriteRef(slug: 'tech')));
  });

  test('rollback on FavoriteCapReachedException', () async {
    final repo = _FakeRepo(seed())..throwCap = true;
    final container = ProviderContainer(overrides: [
      userInterestsRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);

    await container.read(userInterestsProvider.future);

    expect(
      () => container.read(userInterestsProvider.notifier).setInterestState(
          const ThemeFavoriteRef(slug: 'tech'), InterestState.favorite),
      throwsA(isA<FavoriteCapReachedException>()),
    );

    // Need to pump microtask queue for the catch+rollback to apply.
    await Future<void>.delayed(Duration.zero);

    final after = container.read(userInterestsProvider).value!;
    expect(after.favorites, isEmpty);
    expect(after.favoriteCount, 0);
  });
}
