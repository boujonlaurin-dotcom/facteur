import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../custom_topics/providers/personalization_provider.dart';
import '../../digest/providers/digest_provider.dart';
import '../../feed/providers/feed_provider.dart';
import '../../feed/repositories/personalization_repository.dart';
import '../../flux_continu/providers/flux_continu_provider.dart';

/// État du filtre langue (PR 6.1 — couverture FR-first).
///
/// `hideNonFr` : masque les sources non-FR (sauf sources suivies).
/// `userSet` : `true` dès que l'utilisateur a touché manuellement au toggle —
/// gèle le recalcul auto serveur sur follow/unfollow.
/// `synced` : `true` une fois la phase Hive + sync backend terminée (succès
/// ou échec). Évite les flashs d'état par défaut au boot.
@immutable
class LanguagePreferenceState {
  final bool hideNonFr;
  final bool userSet;
  final bool synced;

  const LanguagePreferenceState({
    this.hideNonFr = true,
    this.userSet = false,
    this.synced = false,
  });

  LanguagePreferenceState copyWith({
    bool? hideNonFr,
    bool? userSet,
    bool? synced,
  }) {
    return LanguagePreferenceState(
      hideNonFr: hideNonFr ?? this.hideNonFr,
      userSet: userSet ?? this.userSet,
      synced: synced ?? this.synced,
    );
  }
}

/// Pilote le toggle "Masquer les sources non françaises" + son alignement
/// auto (refresh) après follow/unfollow tant que `userSet = false`.
///
/// Hive = cache pour first-paint ; backend = source of truth.
class LanguagePreferenceNotifier
    extends StateNotifier<LanguagePreferenceState> {
  LanguagePreferenceNotifier(this._ref)
      : super(const LanguagePreferenceState()) {
    unawaited(_bootstrap());
  }

  final Ref _ref;

  static const _boxName = 'settings';
  static const _kHideNonFr = 'hide_non_fr_sources';
  static const _kLanguageUserSet = 'language_filter_user_set';

  Future<Box<dynamic>> _box() => Hive.openBox<dynamic>(_boxName);

  Future<void> _bootstrap() async {
    await _loadFromHive();
    try {
      await _syncFromBackend();
    } finally {
      if (mounted) state = state.copyWith(synced: true);
    }
  }

  Future<void> _loadFromHive() async {
    final box = await _box();
    if (!mounted) return;
    state = LanguagePreferenceState(
      hideNonFr: box.get(_kHideNonFr, defaultValue: true) as bool,
      userSet: box.get(_kLanguageUserSet, defaultValue: false) as bool,
    );
  }

  Future<void> _persist(LanguagePreferenceState s) async {
    final box = await _box();
    await box.putAll({
      _kHideNonFr: s.hideNonFr,
      _kLanguageUserSet: s.userSet,
    });
  }

  Future<void> _syncFromBackend() async {
    try {
      _ref.invalidate(personalizationProvider);
      final perso = await _ref.read(personalizationProvider.future);
      if (!mounted) return;
      final fresh = state.copyWith(
        hideNonFr: perso.hideNonFrSources,
        userSet: perso.languageFilterUserSet,
      );
      state = fresh;
      await _persist(fresh);
    } catch (e) {
      debugPrint('LanguagePreference: backend sync failed: $e');
    }
  }

  /// Optimistic toggle : met à jour le state + Hive immédiatement, puis POST.
  /// Sur erreur, rollback + retourne `false` pour que l'UI affiche une snackbar.
  Future<bool> toggle(bool value) async {
    final previous = state;
    state = state.copyWith(hideNonFr: value, userSet: true);
    await _persist(state);

    try {
      final repo = _ref.read(personalizationRepositoryProvider);
      await repo.toggleHideNonFrSources(value);
      _ref.invalidate(feedProvider);
      _ref.invalidate(digestProvider);
      _ref.invalidate(fluxContinuProvider);
      return true;
    } catch (e) {
      debugPrint('LanguagePreference.toggle failed: $e');
      if (mounted) {
        state = previous;
        await _persist(previous);
      }
      return false;
    }
  }

  /// Resync depuis `/personalization` — appelé après follow/unfollow puisque
  /// le serveur peut basculer auto `hideNonFr` tant que `userSet = false`.
  /// No-op si `userSet = true` (le serveur ne touche plus la valeur, donc
  /// inutile de payer N round-trips pendant un onboarding bulk).
  Future<void> refresh() async {
    if (state.userSet) return;
    await _syncFromBackend();
  }
}

final languagePreferenceProvider = StateNotifierProvider<
    LanguagePreferenceNotifier, LanguagePreferenceState>(
  (ref) => LanguagePreferenceNotifier(ref),
);
