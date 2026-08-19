import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// SharedPreferences instance injected by the app bootstrap.
///
/// Unit tests and providers that are allowed to await can omit the override:
/// [TourneeProgressService] will lazily call [SharedPreferences.getInstance].
final sharedPreferencesProvider = Provider<SharedPreferences?>((ref) => null);

final tourneeProgressServiceProvider = Provider<TourneeProgressService>((ref) {
  return TourneeProgressService(prefs: ref.watch(sharedPreferencesProvider));
});

const String kClosingPrefsKeyPrefix = 'flux_continu_closing_dismissed_';
const String kEssentielViewedPrefsKeyPrefix = 'flux_continu_essentiel_viewed_';

/// Préfixe de la clé jumelle du rituel matinal (« moment d'ouverture »,
/// symétrique de la closing card). `morning_ritual_shown_${dayKey}` mémorise
/// que l'écran enveloppe a été ouvert pour la journée tournée courante, pour
/// ne le montrer qu'une fois par jour (cf. Story 28.1).
const String kMorningRitualPrefsKeyPrefix = 'morning_ritual_shown_';

/// Ordre des blocs de la Tournée trié par score, gelé pour la journée (PR-4).
///
/// Clé **unique** (pas de préfixe daté) stockant un blob JSON
/// `{"day": ..., "keys": [...]}` : le jour vit dans la valeur, donc la clé
/// s'auto-invalide au changement de journée tournée et n'a rien à faire dans
/// `purgeOldPrefsKeys` — une seule entrée, jamais d'accumulation.
const String kTourneeScoreOrderKey = 'tournee_score_order_v1';

/// Articles balayés (« masquer ») pendant la journée tournée courante.
///
/// Même forme auto-invalidante que [kTourneeScoreOrderKey] : `{"day": ...,
/// "ids": [...]}`. Nécessaire depuis le SWR in-day — les sections étant
/// rejouées depuis le cache local à la réouverture, un `_dismissedIds` en
/// mémoire seule ferait **réapparaître** l'article que l'utilisateur venait de
/// balayer (le pire ressenti possible).
const String kTourneeDismissedIdsKey = 'tournee_dismissed_ids_v1';

/// Boundary hour (Paris time) at which the "tournée day" flips.
const int kTourneeDayBoundaryHour = 7;
const int kTourneeDayBoundaryMinute = 30;
const String kTourneeDayBoundaryTz = 'Europe/Paris';

tz.Location? _parisLocation;

tz.Location _parisTz() {
  if (_parisLocation != null) return _parisLocation!;
  tz_data.initializeTimeZones();
  return _parisLocation = tz.getLocation(kTourneeDayBoundaryTz);
}

class TourneeProgressService {
  final SharedPreferences? _prefsOverride;

  const TourneeProgressService({SharedPreferences? prefs})
      : _prefsOverride = prefs;

  Future<SharedPreferences> _prefs() async =>
      _prefsOverride ?? await SharedPreferences.getInstance();

  /// Returns the canonical ISO day (`YYYY-MM-DD`) for the tournée at [now],
  /// using a 07:30 Europe/Paris boundary instead of midnight.
  static String dayKey(DateTime now) {
    final paris = tz.TZDateTime.from(now, _parisTz());
    final shifted = (paris.hour < kTourneeDayBoundaryHour ||
            (paris.hour == kTourneeDayBoundaryHour &&
                paris.minute < kTourneeDayBoundaryMinute))
        ? paris.subtract(const Duration(days: 1))
        : paris;
    return shifted.toIso8601String().substring(0, 10);
  }

  /// Jette les clés datées de [prefix] autres que [keep]. Motif partagé par
  /// tous les compteurs à suffixe jour de l'app (état de tri, nudges d'aperçu) :
  /// sans purge, une clé par jour s'accumule dans `SharedPreferences` à vie.
  static Future<void> purgeDatedPrefsKeys(
    SharedPreferences prefs, {
    required String prefix,
    required String keep,
  }) async {
    final stale =
        prefs.getKeys().where((k) => k.startsWith(prefix) && k != keep).toList();
    await Future.wait(stale.map(prefs.remove));
  }

  static String closingPrefsKey(DateTime day) =>
      '$kClosingPrefsKeyPrefix${dayKey(day)}';

  static String essentielViewedPrefsKey(DateTime day) =>
      '$kEssentielViewedPrefsKeyPrefix${dayKey(day)}';

  bool isClosingDismissedTodaySync({DateTime? now}) {
    final prefs = _prefsOverride;
    if (prefs == null) return false;
    return prefs.getBool(closingPrefsKey(now ?? DateTime.now())) ?? false;
  }

  Future<bool> loadClosingDismissedForToday({DateTime? now}) async {
    try {
      final prefs = await _prefs();
      return prefs.getBool(closingPrefsKey(now ?? DateTime.now())) ?? false;
    } catch (e) {
      debugPrint('TourneeProgress: loadClosingDismissedForToday failed: $e');
      return false;
    }
  }

  Future<void> setClosingDismissedToday(bool dismissed, {DateTime? now}) async {
    try {
      final prefs = await _prefs();
      await prefs.setBool(closingPrefsKey(now ?? DateTime.now()), dismissed);
    } catch (e) {
      debugPrint('TourneeProgress: setClosingDismissedToday failed: $e');
    }
  }

  /// Clé historique « rituel matinal vu aujourd'hui ». Plus personne ne l'écrit
  /// ni ne la lit depuis que la « Lettre du jour » a cessé de gater L'Essentiel
  /// (décision PO 02/08/2026) ; elle survit uniquement pour que
  /// [purgeOldPrefsKeys] nettoie les clés restées sur les appareils déjà
  /// installés. À supprimer une fois le parc renouvelé.
  static String morningRitualPrefsKey(DateTime day) =>
      '$kMorningRitualPrefsKeyPrefix${dayKey(day)}';

  bool isEssentielViewedTodaySync({DateTime? now}) {
    final prefs = _prefsOverride;
    if (prefs == null) return false;
    return prefs.getBool(essentielViewedPrefsKey(now ?? DateTime.now())) ??
        false;
  }

  /// `true` ssi l'utilisateur a déjà « parcouru » l'Essentiel aujourd'hui —
  /// soit en fermant explicitement le bandeau, soit en ayant chargé son
  /// contenu. Sert à router vers Flâner par défaut (cold start / resume).
  bool hasBrowsedEssentielTodaySync({DateTime? now}) =>
      isClosingDismissedTodaySync(now: now) ||
      isEssentielViewedTodaySync(now: now);

  Future<void> markEssentielViewedToday({DateTime? now}) async {
    try {
      final prefs = await _prefs();
      await prefs.setBool(essentielViewedPrefsKey(now ?? DateTime.now()), true);
    } catch (e) {
      debugPrint('TourneeProgress: markEssentielViewedToday failed: $e');
    }
  }

  /// Ordre des blocs gelé **pour la journée tournée courante**, ou `null` si
  /// rien n'est stocké / si l'entrée date d'un jour précédent (auquel cas
  /// l'appelant recalculera un ordre frais à la complétion du fan-out).
  Future<List<String>?> loadScoreOrderForToday({DateTime? now}) async {
    try {
      final prefs = await _prefs();
      final raw = prefs.getString(kTourneeScoreOrderKey);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      if (decoded['day'] != dayKey(now ?? DateTime.now())) return null;
      final keys = decoded['keys'];
      if (keys is! List) return null;
      return <String>[
        for (final k in keys)
          if (k is String) k,
      ];
    } catch (e) {
      debugPrint('TourneeProgress: loadScoreOrderForToday failed: $e');
      return null;
    }
  }

  /// Blocs jugés **pauvres** (curation du jour) au moment du gel, ou `null` aux
  /// mêmes conditions que [loadScoreOrderForToday]. Stocké dans la même entrée :
  /// le déclassement est gelé avec l'ordre, à partir des mêmes scores, donc il
  /// ne peut pas en diverger. Entrée écrite avant ce champ ⇒ `poor` absent ⇒
  /// ensemble vide (aucun déclassement), pas d'invalidation du jour.
  Future<Set<String>?> loadPoorKeysForToday({DateTime? now}) async {
    try {
      final prefs = await _prefs();
      final raw = prefs.getString(kTourneeScoreOrderKey);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      if (decoded['day'] != dayKey(now ?? DateTime.now())) return null;
      final poor = decoded['poor'];
      if (poor is! List) return const <String>{};
      return <String>{
        for (final k in poor)
          if (k is String) k,
      };
    } catch (e) {
      debugPrint('TourneeProgress: loadPoorKeysForToday failed: $e');
      return null;
    }
  }

  /// Articles balayés aujourd'hui (vide si l'entrée date d'un autre jour, est
  /// absente ou illisible — un balayage réapparu vaut mieux qu'un crash).
  Future<Set<String>> loadDismissedIdsForToday({DateTime? now}) async {
    try {
      final prefs = await _prefs();
      final raw = prefs.getString(kTourneeDismissedIdsKey);
      if (raw == null) return const <String>{};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const <String>{};
      if (decoded['day'] != dayKey(now ?? DateTime.now())) {
        return const <String>{};
      }
      final ids = decoded['ids'];
      if (ids is! List) return const <String>{};
      return <String>{
        for (final id in ids)
          if (id is String) id,
      };
    } catch (e) {
      debugPrint('TourneeProgress: loadDismissedIdsForToday failed: $e');
      return const <String>{};
    }
  }

  Future<void> setDismissedIdsToday(
    Set<String> ids, {
    DateTime? now,
  }) async {
    try {
      final prefs = await _prefs();
      await prefs.setString(
        kTourneeDismissedIdsKey,
        jsonEncode({
          'day': dayKey(now ?? DateTime.now()),
          'ids': ids.toList(),
        }),
      );
    } catch (e) {
      debugPrint('TourneeProgress: setDismissedIdsToday failed: $e');
    }
  }

  Future<void> setScoreOrderToday(
    List<String> keys, {
    Set<String> poorKeys = const {},
    DateTime? now,
  }) async {
    try {
      final prefs = await _prefs();
      await prefs.setString(
        kTourneeScoreOrderKey,
        jsonEncode({
          'day': dayKey(now ?? DateTime.now()),
          'keys': keys,
          'poor': poorKeys.toList(),
        }),
      );
    } catch (e) {
      debugPrint('TourneeProgress: setScoreOrderToday failed: $e');
    }
  }

  Future<void> purgeOldPrefsKeys({DateTime? now}) async {
    try {
      final prefs = await _prefs();
      final today = now ?? DateTime.now();
      final closingToday = closingPrefsKey(today);
      final essentielViewedToday = essentielViewedPrefsKey(today);
      // Purge stale closing-dismissed/essentiel-viewed keys (previous days),
      // **all** `morning_ritual_shown_*` keys (today included: nothing reads or
      // writes them since the Lettre stopped gating L'Essentiel), **and** any
      // leftover `flux_continu_folded_*` blobs from before the fold mechanic was
      // removed (2026-06), so they don't linger in SharedPreferences forever.
      final stale = prefs.getKeys().where((k) {
        if (k.startsWith('flux_continu_folded_')) return true;
        if (k.startsWith(kMorningRitualPrefsKeyPrefix)) return true;
        if (k.startsWith(kClosingPrefsKeyPrefix) && k != closingToday) {
          return true;
        }
        if (k.startsWith(kEssentielViewedPrefsKeyPrefix) &&
            k != essentielViewedToday) {
          return true;
        }
        return false;
      }).toList();
      await Future.wait(stale.map(prefs.remove));
    } catch (e) {
      debugPrint('TourneeProgress: purgeOldPrefsKeys failed: $e');
    }
  }
}
