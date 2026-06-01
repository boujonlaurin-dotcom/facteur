import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/nudges/nudge_counters.dart';
import 'weather_location_provider.dart';

/// Nombre d'ouvertures du feed requis avant de proposer la géoloc (jamais à
/// l'onboarding — la météo doit d'abord être un repère quotidien).
const int kGeolocPromptMinFeedOpens = 5;

/// Cap dur : au plus 3 affichages de la bannière au total.
const int kGeolocPromptMaxShown = 3;

/// Persistance Hive (box `settings`) de l'état de la bannière géoloc, même
/// pattern que les clés re-nudge notifications.
class GeolocPromptController {
  GeolocPromptController(this._ref);

  final Ref _ref;

  static const _boxName = 'settings';
  static const kShownCount = 'geoloc_prompt_shown_count';
  static const kLastAt = 'geoloc_prompt_last_at';
  static const kDismissed = 'geoloc_prompt_dismissed';

  Future<Box<dynamic>> _box() => Hive.openBox<dynamic>(_boxName);

  /// Enregistre un affichage (incrémente le cap). Appelé une fois par affichage
  /// effectif de la bannière. Retourne le numéro d'affichage (1-based) pour le
  /// tracking analytics.
  Future<int> recordShown() async {
    final box = await _box();
    final next = (box.get(kShownCount, defaultValue: 0) as int) + 1;
    await box.putAll({
      kShownCount: next,
      kLastAt: DateTime.now().toIso8601String(),
    });
    _ref.invalidate(geolocPromptShouldShowProvider);
    return next;
  }

  /// Coupe définitivement la bannière (option « ne plus afficher »). Non câblé
  /// au bouton « Pas maintenant » (qui ne fait qu'un dismiss de session), mais
  /// disponible si besoin.
  Future<void> dismissPermanently() async {
    final box = await _box();
    await box.put(kDismissed, true);
    _ref.invalidate(geolocPromptShouldShowProvider);
  }
}

final geolocPromptControllerProvider =
    Provider<GeolocPromptController>((ref) => GeolocPromptController(ref));

/// `true` si la bannière de demande de géoloc doit s'afficher :
/// ≥5 ouvertures du feed ET pas déjà en position device ET cap non atteint ET
/// pas coupée définitivement.
final geolocPromptShouldShowProvider = FutureProvider<bool>((ref) async {
  final location = ref.watch(weatherLocationProvider);
  if (location.isDeviceLocation) return false;

  try {
    final box = await Hive.openBox<dynamic>('settings');
    if (box.get(GeolocPromptController.kDismissed, defaultValue: false)
        as bool) {
      return false;
    }
    final shownCount =
        box.get(GeolocPromptController.kShownCount, defaultValue: 0) as int;
    if (shownCount >= kGeolocPromptMaxShown) return false;
  } catch (e) {
    debugPrint('GeolocPrompt: Hive read failed: $e');
    return false;
  }

  final feedOpens = await NudgeCounters.get(NudgeCounters.feedOpenCount);
  return feedOpens >= kGeolocPromptMinFeedOpens;
});
