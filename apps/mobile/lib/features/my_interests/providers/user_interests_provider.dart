/// Story 22.1 — provider canonique des intérêts utilisateur.
///
/// Source de vérité unique côté mobile pour Thèmes + Sujets (4-états + favoris ordonnés).
/// Pattern optimistic update : mutation locale → fire API → rollback si erreur.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_interests_state.dart';
import '../repositories/user_interests_repository.dart';

class UserInterestsNotifier extends AsyncNotifier<UserInterestsState> {
  @override
  Future<UserInterestsState> build() async {
    final repo = ref.watch(userInterestsRepositoryProvider);
    return repo.fetchInterests();
  }

  /// Mute l'état d'un Thème ou Sujet. Optimistic + rollback.
  /// Lève [FavoriteCapReachedException] (re-throw) pour que l'appelant affiche
  /// un snackbar « tu as déjà 3 favoris ».
  Future<void> setInterestState(
    FavoriteRef refTarget,
    InterestState newState,
  ) async {
    final current = state.value;
    if (current == null) return;

    final repo = ref.read(userInterestsRepositoryProvider);
    final previousState = state;

    final optimistic = _applyLocal(current, refTarget, newState);
    state = AsyncValue.data(optimistic);

    try {
      final updated = await repo.setInterestState(
        ref: refTarget,
        state: newState,
      );
      state = AsyncValue.data(updated);
    } on FavoriteCapReachedException {
      state = previousState;
      rethrow;
    } catch (e, st) {
      state = previousState;
      // ignore: avoid_print
      print('UserInterestsNotifier: setInterestState failed: $e\n$st');
      rethrow;
    }
  }

  /// Réordonne la liste des favoris. Optimistic + rollback.
  Future<void> reorderFavorites(List<FavoriteRef> ordered) async {
    final current = state.value;
    if (current == null) return;

    final repo = ref.read(userInterestsRepositoryProvider);
    final previousState = state;

    state = AsyncValue.data(current.copyWith(favorites: ordered));

    try {
      final updated = await repo.reorderFavorites(ordered);
      state = AsyncValue.data(updated);
    } catch (e, st) {
      state = previousState;
      // ignore: avoid_print
      print('UserInterestsNotifier: reorderFavorites failed: $e\n$st');
      rethrow;
    }
  }

  /// Applique la mutation localement : update theme/topic state + recompute favorites.
  UserInterestsState _applyLocal(
    UserInterestsState current,
    FavoriteRef refTarget,
    InterestState newState,
  ) {
    final themes = [...current.themes];
    final customTopics = [...current.customTopics];

    switch (refTarget) {
      case ThemeFavoriteRef(:final slug):
        final idx = themes.indexWhere((t) => t.interestSlug == slug);
        if (idx >= 0) {
          themes[idx] = themes[idx].copyWith(state: newState);
        } else {
          themes.add(
            ThemeInterest(
              interestSlug: slug,
              weight: 1.0,
              state: newState,
            ),
          );
        }
      case CustomTopicFavoriteRef(:final id):
        final idx = customTopics.indexWhere((t) => t.id == id);
        if (idx >= 0) {
          customTopics[idx] = customTopics[idx].copyWith(state: newState);
        }
      case VeilleFavoriteRef():
        // La veille n'a pas d'entrée themes/customTopics — son état est
        // implicite (présence dans `favorites` = favori, suppression =
        // archive via DELETE /api/veille/config). Pas de mutation locale ici.
        break;
    }

    var favorites = [...current.favorites];
    final isAlreadyFavorite = favorites.contains(refTarget);
    if (newState == InterestState.favorite && !isAlreadyFavorite) {
      favorites = [...favorites, refTarget];
    } else if (newState != InterestState.favorite && isAlreadyFavorite) {
      favorites = favorites.where((f) => f != refTarget).toList();
    }

    return current.copyWith(
      themes: themes,
      customTopics: customTopics,
      favorites: favorites,
      favoriteCount: favorites.length,
    );
  }
}

final userInterestsProvider =
    AsyncNotifierProvider<UserInterestsNotifier, UserInterestsState>(
  UserInterestsNotifier.new,
);
