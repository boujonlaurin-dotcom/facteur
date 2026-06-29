import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../gamification/providers/streak_activity_provider.dart';
import '../utils/morning_ritual_format.dart';
import 'selected_edition_date_provider.dart';

/// EPIC « Lettre du jour » — statut **lu / non-lu** de la timeline Essentiel.
///
/// Réutilise la feature **streaks** (`streakActivityProvider`, `opened` par
/// jour) — zéro changement back-end — unie à un petit set **local** « rattrapé »
/// pour que l'action de rattrapage d'un jour soit ressentie immédiatement.

/// Clé SharedPreferences du set local « éditions rattrapées » (dayKeys
/// `YYYY-MM-DD`). Frontend-only : complète streaks sans aller-retour back-end.
const String kEditionCaughtUpPrefsKey = 'edition_caught_up_v1';

/// Borne défensive : on ne conserve que les [_kCaughtUpMaxEntries] clés les plus
/// récentes (tri lexical == chronologique sur `YYYY-MM-DD`) pour éviter une
/// croissance illimitée au fil des jours.
const int _kCaughtUpMaxEntries = 60;

/// Set local des dayKeys d'éditions passées rattrapées. Mirroir du pattern
/// prefs de [TourneeOrderPrefsNotifier] (StringList + best-effort).
final editionCaughtUpProvider =
    StateNotifierProvider<EditionCaughtUpNotifier, Set<String>>((ref) {
  return EditionCaughtUpNotifier();
});

class EditionCaughtUpNotifier extends StateNotifier<Set<String>> {
  EditionCaughtUpNotifier() : super(const <String>{}) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(kEditionCaughtUpPrefsKey) ?? const [];
      if (mounted) state = Set.unmodifiable(list);
    } catch (e) {
      // Pas de prefs (ex. tests sans mock) → set vide.
      debugPrint('EditionCaughtUp: load failed: $e');
    }
  }

  /// Marque l'édition [dayKey] (`YYYY-MM-DD`) comme rattrapée. No-op si déjà
  /// présente. Best-effort sur les prefs : l'état mémoire reste appliqué pour la
  /// session même si l'écriture disque échoue.
  Future<void> markCaughtUp(String dayKey) async {
    if (state.contains(dayKey)) return;
    final sorted = <String>{...state, dayKey}.toList()..sort();
    final trimmed = sorted.length > _kCaughtUpMaxEntries
        ? sorted.sublist(sorted.length - _kCaughtUpMaxEntries)
        : sorted;
    state = Set.unmodifiable(trimmed);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(kEditionCaughtUpPrefsKey, trimmed);
    } catch (e) {
      debugPrint('EditionCaughtUp: markCaughtUp failed: $e');
    }
  }
}

/// Statut « lu / non-lu » des éditions de la timeline.
///
/// Quand [available] vaut `false` (streaks désactivé/indisponible, ou en
/// chargement/erreur), la timeline n'affiche **aucun** statut (dégradation
/// gracieuse) : la navigation temporelle fonctionne quand même.
class EditionReadStatus {
  /// `false` ⇒ aucune pastille ni libellé affiché.
  final bool available;

  /// dayKeys (`YYYY-MM-DD`) considérés « à jour » : `opened == true` côté streaks
  /// **ou** présents dans le set local « rattrapé ».
  final Set<String> readDayKeys;

  const EditionReadStatus({
    required this.available,
    this.readDayKeys = const <String>{},
  });

  const EditionReadStatus.unavailable()
      : available = false,
        readDayKeys = const <String>{};

  /// L'édition [selection] est-elle « à jour » ? À n'appeler que lorsque
  /// [available] vaut `true`.
  /// - `today` : toujours « à jour » (on est dans l'app) ;
  /// - jour passé : à jour ssi son dayKey ∈ [readDayKeys] ;
  /// - « Cette semaine » : à jour ssi aucun jour J-0…J-6 n'est non-lu.
  bool isEditionRead(EditionSelection selection, {DateTime? now}) {
    switch (selection) {
      case EditionToday():
        return true;
      case EditionPastDay(:final date):
        return readDayKeys.contains(editionDayKey(date));
      case EditionWeek():
        // J-0 (today) est toujours lu ; il reste J-1…J-6 à vérifier.
        for (final date in editionPastDays(6, now: now)) {
          if (!readDayKeys.contains(editionDayKey(date))) return false;
        }
        return true;
    }
  }
}

/// Statut lu/non-lu dérivé : union des jours `opened` de streaks et du set local
/// « rattrapé ». NB frontière de jour : on compare via [editionDayKey] des deux
/// côtés (best-effort) ; un éventuel off-by-one streaks (TZ serveur) vs la
/// frontière 7h30 Paris des éditions est audité dans le hand-off « santé des
/// streaks » (cf. `.context/streaks-health-handoff.md`).
final editionReadStatusProvider = Provider<EditionReadStatus>((ref) {
  final activityAsync = ref.watch(streakActivityProvider);
  final caughtUp = ref.watch(editionCaughtUpProvider);
  final activity = activityAsync.valueOrNull;
  // Dégradation gracieuse : loading/error (valueOrNull == null) OU activity vide
  // (gamification off → StreakActivityModel.empty, days == []) ⇒ aucun statut.
  if (activity == null || activity.days.isEmpty) {
    return const EditionReadStatus.unavailable();
  }
  final read = <String>{
    for (final d in activity.days)
      if (d.opened) editionDayKey(d.date),
    ...caughtUp,
  };
  return EditionReadStatus(available: true, readDayKeys: read);
});
