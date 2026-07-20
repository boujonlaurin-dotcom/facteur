import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Préfixe de la clé « compteur du jour » (`..._<yyyy-mm-dd>`) : borne le nombre
/// de pulses auto-grow par jour calendaire. Le suffixe daté rend le reset
/// gratuit (une nouvelle clé = 0 le lendemain).
const String kAutoGrowCountPrefixPrefsKey = 'auto_grow_nudge_count_';

/// Timestamp (ms epoch) du dernier pulse déclenché — sert à imposer l'espacement.
const String kAutoGrowLastTriggerPrefsKey = 'auto_grow_nudge_last_trigger_ms';

/// Flag « l'utilisateur a découvert l'aperçu » (vrai long-press) — arrête
/// définitivement le nudge pour cet utilisateur.
const String kAutoGrowDiscoveredPrefsKey = 'auto_grow_nudge_discovered';

/// Budget quotidien de pulses auto-grow.
const int kAutoGrowDailyBudget = 3;

/// Espacement minimum entre deux pulses (répartit les ~3/jour sur la journée
/// plutôt que de les enchaîner dans la même session).
const Duration kAutoGrowMinSpacing = Duration(minutes: 90);

/// Coordinateur du nudge auto-grow « découvre l'aperçu au long-press ».
///
/// Volontairement **hors** de `NudgeRegistry`/`NudgeCoordinator` : aucune
/// fréquence existante ne correspond à « plusieurs fois par jour, espacées », et
/// ce nudge doit justement échapper au cooldown global ~24h du coordinator.
///
/// Persistance `SharedPreferences`, `clock`/`prefs` injectables pour les tests
/// (même pattern que `WellInformedPromptController`).
class AutoGrowNudgeScheduler {
  AutoGrowNudgeScheduler({
    DateTime Function()? clock,
    Future<SharedPreferences> Function()? prefs,
    int dailyBudget = kAutoGrowDailyBudget,
    Duration minSpacing = kAutoGrowMinSpacing,
  })  : _clock = clock ?? DateTime.now,
        _prefsFactory = prefs ?? SharedPreferences.getInstance,
        _dailyBudget = dailyBudget,
        _minSpacing = minSpacing;

  final DateTime Function() _clock;
  final Future<SharedPreferences> Function() _prefsFactory;
  final int _dailyBudget;
  final Duration _minSpacing;

  /// Vrai si un pulse peut être déclenché maintenant :
  ///   - l'utilisateur n'a PAS déjà découvert l'aperçu, ET
  ///   - le budget du jour n'est pas épuisé, ET
  ///   - l'espacement minimum depuis le dernier pulse est écoulé.
  Future<bool> canTriggerNow() async {
    final prefs = await _prefsFactory();
    if (prefs.getBool(kAutoGrowDiscoveredPrefsKey) ?? false) return false;

    final now = _clock();
    if ((prefs.getInt(_countKey(now)) ?? 0) >= _dailyBudget) return false;

    final lastMs = prefs.getInt(kAutoGrowLastTriggerPrefsKey);
    if (lastMs != null) {
      final last = DateTime.fromMillisecondsSinceEpoch(lastMs);
      if (now.difference(last) < _minSpacing) return false;
    }
    return true;
  }

  /// Enregistre un pulse déclenché : incrémente le compteur du jour et pose le
  /// timestamp du dernier trigger.
  Future<void> recordTriggered() async {
    final prefs = await _prefsFactory();
    final now = _clock();
    final key = _countKey(now);
    await prefs.setInt(key, (prefs.getInt(key) ?? 0) + 1);
    await prefs.setInt(
      kAutoGrowLastTriggerPrefsKey,
      now.millisecondsSinceEpoch,
    );
  }

  /// Marque l'aperçu comme découvert (vrai long-press utilisateur) → arrête
  /// définitivement le nudge.
  Future<void> markDiscovered() async {
    final prefs = await _prefsFactory();
    await prefs.setBool(kAutoGrowDiscoveredPrefsKey, true);
  }

  String _countKey(DateTime now) {
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$kAutoGrowCountPrefixPrefsKey${now.year}-$m-$d';
  }
}

/// Instance partagée du scheduler (prod : horloge + prefs réelles).
final autoGrowNudgeSchedulerProvider = Provider<AutoGrowNudgeScheduler>(
  (ref) => AutoGrowNudgeScheduler(),
);
