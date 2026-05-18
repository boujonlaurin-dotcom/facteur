/// Story 22.1 PR 3/3 — sync one-shot des préférences héritées du slider 1→3
/// (SharedPreferences `theme_priority_<MacroLabel>`) vers le backend post-MeP.
///
/// Le slider mobile écrivait `multiplier` ∈ {1.0, 2.0, 3.0} dans SharedPreferences
/// uniquement (jamais en DB). Le backfill SQL de la migration 22a1 ne peut donc
/// pas voir ces valeurs. Ce service les lit au prochain lancement post-migration,
/// promeut en favori côté backend chaque thème à `>= 2.0`, puis purge les clés.
///
/// Idempotent via le flag `_kSyncFlag`. Fire-and-forget : aucun call-site ne doit
/// `await` le retour. Les erreurs réseau et `FavoriteCapReachedException` sont
/// silencieusement absorbées (le user a déjà été backfillé par la migration).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/topic_labels.dart';
import '../../../core/auth/auth_state.dart';
import '../models/user_interests_state.dart';
import '../repositories/user_interests_repository.dart';

class InterestsSyncService {
  static const String _kSyncFlag = 'interests_v2_legacy_synced';
  static const String _kLegacyPrefix = 'theme_priority_';
  static const double _kPromoteThreshold = 2.0;

  final UserInterestsRepository _repository;
  final Future<SharedPreferences> Function() _prefsFactory;

  InterestsSyncService({
    required UserInterestsRepository repository,
    Future<SharedPreferences> Function()? prefsFactory,
  })  : _repository = repository,
        _prefsFactory = prefsFactory ?? SharedPreferences.getInstance;

  /// Sync one-shot. Safe à appeler depuis n'importe quel startup hook.
  Future<void> syncLegacyThemePreferences() async {
    final prefs = await _prefsFactory();
    if (prefs.getBool(_kSyncFlag) ?? false) return;

    final legacyKeys = prefs
        .getKeys()
        .where((k) => k.startsWith(_kLegacyPrefix))
        .toList(growable: false);

    final slugsToPromote = _extractPromotableSlugs(prefs, legacyKeys);

    for (final slug in slugsToPromote) {
      try {
        await _repository.setInterestState(
          ref: ThemeFavoriteRef(slug: slug),
          state: InterestState.favorite,
        );
      } on FavoriteCapReachedException {
        // Backfill backend a déjà rempli le cap, ou un précédent sync l'a fait.
      } catch (e) {
        debugPrint('[InterestsSync] failed for $slug: $e');
      }
    }

    for (final k in legacyKeys) {
      await prefs.remove(k);
    }
    await prefs.setBool(_kSyncFlag, true);
  }

  List<String> _extractPromotableSlugs(
    SharedPreferences prefs,
    List<String> legacyKeys,
  ) {
    final out = <String>[];
    for (final key in legacyKeys) {
      final multiplier = prefs.getDouble(key) ?? 1.0;
      if (multiplier < _kPromoteThreshold) continue;
      final macroLabel = key.substring(_kLegacyPrefix.length);
      final apiSlug = macroThemeToApiSlug[macroLabel];
      if (apiSlug != null) out.add(apiSlug);
    }
    return out;
  }
}

/// Service Provider (DI-friendly). Override-able dans les tests.
final interestsSyncServiceProvider = Provider<InterestsSyncService>((ref) {
  final repo = ref.watch(userInterestsRepositoryProvider);
  return InterestsSyncService(repository: repo);
});

/// StateNotifier qui écoute l'auth et déclenche le sync une fois par session
/// dès que le user devient authentifié. Mirroir de `onboardingSyncProvider`.
class _InterestsSyncTrigger extends StateNotifier<void> {
  _InterestsSyncTrigger(this._ref) : super(null) {
    _ref.listen<AuthState>(authStateProvider, (previous, next) {
      final wasAuth = previous?.isAuthenticated ?? false;
      if (!wasAuth && next.isAuthenticated) {
        _fire();
      }
    }, fireImmediately: true);
  }

  final Ref _ref;
  // Garde anti-double-fire intra-session : si l'auth flicker (signedOut →
  // signedIn rapide), le listener pourrait appeler _fire() deux fois avant
  // que le flag SharedPrefs (cross-session) ne soit écrit par le service.
  bool _started = false;

  void _fire() {
    if (_started) return;
    _started = true;
    final service = _ref.read(interestsSyncServiceProvider);
    // Fire-and-forget — toute erreur reste capturée silencieusement
    // dans le service lui-même.
    unawaited(service.syncLegacyThemePreferences());
  }
}

/// À watcher depuis `FacteurApp.build()` pour armer le sync au boot.
final interestsSyncProvider =
    StateNotifierProvider<_InterestsSyncTrigger, void>(
  (ref) => _InterestsSyncTrigger(ref),
);
