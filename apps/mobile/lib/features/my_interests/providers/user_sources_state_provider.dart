/// Story 22.1 — provider 4-états pour les Sources.
///
/// Distinct du `userSourcesProvider` legacy (sources_providers.dart) qui gère
/// trust/weight/mute. Les deux coexistent pour limiter le blast-radius de
/// cette PR au scope `Mes sources`. Une future PR pourra consolider.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_interests_state.dart' show InterestState;
import '../models/user_sources_state.dart';
import '../repositories/user_interests_repository.dart';

class UserSourcesStateNotifier extends AsyncNotifier<UserSourcesState> {
  @override
  Future<UserSourcesState> build() async {
    final repo = ref.watch(userInterestsRepositoryProvider);
    return repo.fetchSourcesState();
  }

  Future<void> setSourceState(String sourceId, InterestState newState) async {
    final current = state.value;
    if (current == null) return;

    final repo = ref.read(userInterestsRepositoryProvider);
    final previousState = state;

    final sources = [...current.sources];
    final idx = sources.indexWhere((s) => s.sourceId == sourceId);
    if (idx >= 0) {
      sources[idx] = sources[idx].copyWith(state: newState);
    } else {
      sources.add(SourceInterest(
        sourceId: sourceId,
        state: newState,
        priorityMultiplier: 1.0,
      ));
    }

    var favorites = [...current.favorites];
    final isFav = favorites.any((f) => f.sourceId == sourceId);
    if (newState == InterestState.favorite && !isFav) {
      favorites = [
        ...favorites,
        SourceFavoriteRef(sourceId: sourceId, position: favorites.length),
      ];
    } else if (newState != InterestState.favorite && isFav) {
      favorites = favorites.where((f) => f.sourceId != sourceId).toList();
    }

    state = AsyncValue.data(current.copyWith(
      sources: sources,
      favorites: favorites,
      favoriteCount: favorites.length,
    ));

    try {
      final updated =
          await repo.setSourceState(sourceId: sourceId, state: newState);
      state = AsyncValue.data(updated);
    } on FavoriteCapReachedException {
      state = previousState;
      rethrow;
    } catch (e, st) {
      state = previousState;
      // ignore: avoid_print
      print('UserSourcesStateNotifier: setSourceState failed: $e\n$st');
      rethrow;
    }
  }

  Future<void> reorderFavorites(List<SourceFavoriteRef> ordered) async {
    final current = state.value;
    if (current == null) return;

    final repo = ref.read(userInterestsRepositoryProvider);
    final previousState = state;

    state = AsyncValue.data(current.copyWith(favorites: ordered));

    try {
      final updated = await repo.reorderSourceFavorites(ordered);
      state = AsyncValue.data(updated);
    } catch (e, st) {
      state = previousState;
      // ignore: avoid_print
      print('UserSourcesStateNotifier: reorderFavorites failed: $e\n$st');
      rethrow;
    }
  }
}

final userSourcesStateProvider =
    AsyncNotifierProvider<UserSourcesStateNotifier, UserSourcesState>(
  UserSourcesStateNotifier.new,
);
