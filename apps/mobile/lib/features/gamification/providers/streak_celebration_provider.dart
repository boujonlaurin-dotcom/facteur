import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../flux_continu/services/tournee_progress_service.dart';
import 'gamification_preference_provider.dart';
import 'streak_animation_provider.dart';

/// Gate 1×/jour-tournée de la **célébration** de streak (« la flamme grossit puis
/// s'incrémente N-1 → N » à l'ouverture de la lettre). Même forme que
/// [StreakDailyAnimationGate] mais :
///   - clé prefs distincte ([_prefsKey]) pour ne pas se marcher dessus avec le
///     simple pulse quotidien ;
///   - **seule déviation du pattern copié** : la frontière de jour utilise
///     [TourneeProgressService.dayKey] (07h30 Europe/Paris) au lieu de minuit
///     local, pour s'aligner sur `morning_ritual_shown_${dayKey}` — la
///     célébration suit ainsi la même journée-tournée que le rituel matinal.
class StreakCelebrationGate {
  StreakCelebrationGate({
    required StreakAnimationClock now,
    Future<SharedPreferences> Function()? prefsFactory,
  }) : _now = now,
       _prefsFactory = prefsFactory ?? SharedPreferences.getInstance;

  static const _prefsKey = 'streak_celebration_last_shown_date';
  final StreakAnimationClock _now;
  final Future<SharedPreferences> Function() _prefsFactory;

  Future<bool> shouldCelebrateToday() async {
    final prefs = await _prefsFactory();
    return prefs.getString(_prefsKey) != _todayKey();
  }

  Future<void> markCelebratedForToday() async {
    final prefs = await _prefsFactory();
    await prefs.setString(_prefsKey, _todayKey());
  }

  // Frontière 07h30 Paris (cf. doc-comment) — l'unique écart au pattern de
  // [StreakDailyAnimationGate], qui découpe à minuit local.
  String _todayKey() => TourneeProgressService.dayKey(_now());
}

final streakCelebrationGateProvider = Provider<StreakCelebrationGate>((ref) {
  // Réutilise l'horloge existante (pas de 2e source de temps).
  return StreakCelebrationGate(now: ref.watch(streakAnimationClockProvider));
});

/// Éligibilité de la célébration : gamification activée **et** gate 1×/jour-tournée
/// pas encore consommé. Miroir de [streakDailyAnimationProvider].
final streakCelebrationEligibleProvider = FutureProvider<bool>((ref) async {
  final enabled = await ref.watch(gamificationPreferenceProvider.future);
  if (!enabled) return false;

  final gate = ref.watch(streakCelebrationGateProvider);
  return gate.shouldCelebrateToday();
});

/// Flag transitoire « on vient d'ouvrir la lettre » (posé dans `_open()` du
/// rituel). Le feed de l'Essentiel est une page racine kept-alive : il ne peut
/// pas se fier à son seul montage pour savoir qu'on arrive du rituel du jour.
final pendingStreakCelebrationProvider =
    StateProvider<bool>((ref) => false);
