import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tournee_progress_service.dart';

/// Préfixe de la clé « déjà montré aujourd'hui » (`..._<dayKey>`). Le suffixe
/// daté rend le reset gratuit : une nouvelle journée = une nouvelle clé absente.
/// La `dayKey` est celle de la Tournée (bascule 07h30 Paris) — le nudge suit
/// donc la même journée que le tri qu'il commente.
const String kTriagePreviewNudgeShownPrefix = 'triage_preview_nudge_shown_';

/// Flag « l'utilisateur a découvert l'aperçu » (vrai long-press sur une carte de
/// tri ou ailleurs) — arrête définitivement le nudge.
const String kTriagePreviewNudgeDiscoveredPrefsKey =
    'triage_preview_nudge_discovered';

/// Index (0-based) de la carte sur laquelle le nudge se déclenche : la
/// **deuxième**. À la première, l'utilisateur découvre le geste de swipe ; lui
/// annoncer un second geste dans la foulée noierait les deux.
const int kTriagePreviewNudgeCardIndex = 1;

/// Durée d'affichage du mini libellé avant auto-masquage — alignée sur le hint
/// de réorganisation des onglets (`flux_continu_screen`).
const Duration kTriagePreviewHintDuration = Duration(milliseconds: 2400);

/// Coordinateur du nudge « aperçu au long-press » de la pile de tri.
///
/// Volontairement **hors** de `NudgeRegistry`/`NudgeCoordinator`, comme
/// `AutoGrowNudgeScheduler` dont il reprend la forme : le cooldown global 24 h
/// et le budget de session du coordinator sont calibrés pour des sollicitations
/// d'écran, pas pour un indice intra-carte joué pendant un geste en cours.
///
/// Fréquence bien plus sobre que l'auto-grow : **une fois par jour au plus**, et
/// plus jamais dès le premier long-press réel.
///
/// Persistance `SharedPreferences`, `clock`/`prefs` injectables pour les tests.
class TriagePreviewNudgeScheduler {
  TriagePreviewNudgeScheduler({
    DateTime Function()? clock,
    Future<SharedPreferences> Function()? prefs,
  })  : _clock = clock ?? DateTime.now,
        _prefsFactory = prefs ?? SharedPreferences.getInstance;

  final DateTime Function() _clock;
  final Future<SharedPreferences> Function() _prefsFactory;

  /// Vrai si le nudge peut être joué maintenant : l'aperçu n'est pas déjà
  /// découvert **et** il n'a pas déjà été montré aujourd'hui.
  Future<bool> canTriggerNow() async {
    final prefs = await _prefsFactory();
    if (prefs.getBool(kTriagePreviewNudgeDiscoveredPrefsKey) ?? false) {
      return false;
    }
    return !(prefs.getBool(_shownKey()) ?? false);
  }

  /// Enregistre le nudge du jour comme joué, et jette au passage les clés des
  /// jours précédents — sans quoi elles s'accumuleraient indéfiniment (même
  /// motif que `EssentielTriageNotifier._purgeStaleKeys`).
  Future<void> recordTriggered() async {
    final prefs = await _prefsFactory();
    final today = _shownKey();
    await prefs.setBool(today, true);
    final stale = prefs
        .getKeys()
        .where((k) => k.startsWith(kTriagePreviewNudgeShownPrefix) && k != today)
        .toList();
    await Future.wait(stale.map(prefs.remove));
  }

  /// Marque l'aperçu comme découvert (vrai long-press) → arrête définitivement
  /// le nudge, sans attendre la fin de la journée.
  Future<void> markDiscovered() async {
    final prefs = await _prefsFactory();
    await prefs.setBool(kTriagePreviewNudgeDiscoveredPrefsKey, true);
  }

  String _shownKey() =>
      '$kTriagePreviewNudgeShownPrefix${TourneeProgressService.dayKey(_clock())}';
}

/// Instance partagée du scheduler (prod : horloge + prefs réelles).
final triagePreviewNudgeSchedulerProvider =
    Provider<TriagePreviewNudgeScheduler>(
  (ref) => TriagePreviewNudgeScheduler(),
);
