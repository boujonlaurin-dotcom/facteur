import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../premium/premium_provider.dart';

const _keyPrefix = 'analyse_quota_';

/// Quota local d'analyses Facteur : 1 lancement offert par jour pour les
/// non-premium. Persisté au device via SharedPreferences (clé
/// `analyse_quota_YYYY-MM-DD`, reset à minuit) — accepté : une réinstall
/// remet le compteur à zéro. State = quota du jour déjà utilisé ?
final analyseQuotaProvider = AsyncNotifierProvider<AnalyseQuotaNotifier, bool>(
  AnalyseQuotaNotifier.new,
);

class AnalyseQuotaNotifier extends AsyncNotifier<bool> {
  String get _todayKey {
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$_keyPrefix${now.year}-$m-$d';
  }

  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    // Purge des clés des jours passés pour ne pas accumuler à l'infini.
    final today = _todayKey;
    for (final key in prefs.getKeys().toList()) {
      if (key.startsWith(_keyPrefix) && key != today) {
        await prefs.remove(key);
      }
    }
    return prefs.getBool(today) ?? false;
  }

  /// L'utilisateur peut-il lancer une analyse fraîche maintenant ?
  /// Premium → toujours. Free → tant que le quota du jour n'est pas consommé.
  bool get canLaunch {
    if (ref.read(isPremiumProvider)) return true;
    return !(state.valueOrNull ?? false);
  }

  /// À appeler uniquement sur un lancement frais (state `idle`), jamais sur
  /// la réouverture d'une analyse déjà cachée. No-op pour les premium.
  Future<void> recordUse() async {
    if (ref.read(isPremiumProvider)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_todayKey, true);
    state = const AsyncData(true);
  }

  /// Gate d'un lancement frais (state `idle`) : consomme le quota du jour et
  /// renvoie `true` si autorisé, `false` si le quota free est déjà épuisé.
  /// Premium → toujours `true` (sans consommer). Centralise l'invariant
  /// [canLaunch] + [recordUse] partagé par les points d'entrée d'analyse.
  bool tryConsume() {
    if (!canLaunch) return false;
    recordUse();
    return true;
  }
}
