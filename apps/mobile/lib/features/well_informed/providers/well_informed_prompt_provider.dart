import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/nudges/nudge_coordinator.dart';
import '../../../core/nudges/nudge_ids.dart';
import '../../../core/nudges/nudge_service.dart';
import '../../notif_du_jour/providers/notif_du_jour_provider.dart'
    show notifIdHash;
import '../data/well_informed_repository.dart';

/// Clé SharedPreferences portant le timestamp de la DERNIÈRE soumission
/// (distincte de `nudge.well_informed_poll.lastShown` utilisée par le service
/// nudges pour tout "shown" — y compris skip). Permet d'imposer 60j après
/// réponse même si le nudge lui-même a un cooldown plus court (pour le skip).
const String kWellInformedLastSubmittedPrefsKey =
    'well_informed_poll_last_submitted_at_ms';

/// Clé SharedPreferences portant le salt aléatoire par installation, tiré une
/// seule fois. Désynchronise le jour d'apparition du sondage entre users (pas
/// de pic le même jour) tout en restant stable dans la journée pour un user
/// donné. Injectable en test (pré-seed la clé).
const String kWellInformedSamplingSaltPrefsKey = 'well_informed_sampling_salt';

/// Cooldown long après une vraie soumission. Porté de 14j → 60j pour rarefier
/// le sondage NPS (irritant "trop fréquent").
const Duration kWellInformedSubmittedCooldown = Duration(days: 60);

/// % de jours *éligibles* (cooldowns passés) où le sondage a le droit
/// d'apparaître — ~1 jour sur 7. Tirage aléatoire **stable par jour
/// calendaire** (cf. `shouldShow`), **non gaté sur l'engagement** : chaque user
/// est également susceptible d'être échantillonné, quel que soit son streak →
/// échantillon non biaisé.
const int kWellInformedDailySamplingPercent = 15;

/// Coordinateur métier du prompt "bien informé".
///
/// - `shouldShow()` : vrai si aucune soumission < 60j, ET le nudge (cooldown
///   configuré dans NudgeRegistry) autorise l'affichage, ET le tirage
///   quotidien stable « sort » (≈15% des jours éligibles).
/// - `recordShown()` : enregistre un shown (sert pour la cooldown skip).
/// - `submit()` : POST la note + marque la soumission + avance le cooldown
///   long (60j).
/// - `skip()` : marque un shown (cooldown court du nudge), pas de POST.
class WellInformedPromptController {
  WellInformedPromptController({
    required NudgeService nudgeService,
    required WellInformedRepository repository,
    DateTime Function()? clock,
    Future<SharedPreferences> Function()? prefs,
    int samplingPercent = kWellInformedDailySamplingPercent,
  })  : _nudgeService = nudgeService,
        _repository = repository,
        _clock = clock ?? DateTime.now,
        _prefsFactory = prefs ?? SharedPreferences.getInstance,
        _samplingPercent = samplingPercent;

  final NudgeService _nudgeService;
  final WellInformedRepository _repository;
  final DateTime Function() _clock;
  final Future<SharedPreferences> Function() _prefsFactory;
  final int _samplingPercent;

  Future<bool> shouldShow() async {
    final prefs = await _prefsFactory();
    final submittedMs = prefs.getInt(kWellInformedLastSubmittedPrefsKey);
    if (submittedMs != null) {
      final last = DateTime.fromMillisecondsSinceEpoch(submittedMs);
      if (_clock().difference(last) < kWellInformedSubmittedCooldown) {
        return false;
      }
    }
    if (!await _nudgeService.canShow(NudgeIds.wellInformedPoll)) {
      return false;
    }
    // Tirage aléatoire quotidien non biaisé : une fois les cooldowns passés, on
    // n'affiche PAS systématiquement — n'autorise l'affichage que sur ~1 jour
    // éligible sur 7. Hash FNV-1a de `salt#yyyy-mm-dd` (stable dans la journée,
    // pas de `Random()` volatile qui flickerait entre rebuilds) mixé à un salt
    // par installation pour désynchroniser le jour entre users.
    final salt = await _samplingSalt(prefs);
    final dayKey = _dayKey(_clock());
    return notifIdHash('$salt#$dayKey') % 100 < _samplingPercent;
  }

  Future<void> recordShown() async {
    await _nudgeService.markShown(NudgeIds.wellInformedPoll);
  }

  Future<void> submit(int score, {String context = 'digest_inline'}) async {
    await _repository.submitRating(score: score, context: context);
    final prefs = await _prefsFactory();
    await prefs.setInt(
      kWellInformedLastSubmittedPrefsKey,
      _clock().millisecondsSinceEpoch,
    );
    await _nudgeService.markShown(NudgeIds.wellInformedPoll);
  }

  Future<void> skip() async {
    await _nudgeService.markShown(NudgeIds.wellInformedPoll);
  }

  /// Salt par installation, tiré une seule fois puis persisté. Stable ensuite,
  /// donc le tirage quotidien ne dépend que du jour calendaire.
  Future<String> _samplingSalt(SharedPreferences prefs) async {
    final existing = prefs.getString(kWellInformedSamplingSaltPrefsKey);
    if (existing != null) return existing;
    final salt = Random().nextInt(1 << 31).toString();
    await prefs.setString(kWellInformedSamplingSaltPrefsKey, salt);
    return salt;
  }

  /// Clé jour calendaire local `yyyy-mm-dd` — constante sur la journée vécue.
  String _dayKey(DateTime now) {
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}-$m-$d';
  }
}

final wellInformedPromptControllerProvider =
    Provider<WellInformedPromptController>((ref) {
  final nudgeService = ref.watch(nudgeServiceProvider);
  final repository = ref.watch(wellInformedRepositoryProvider);
  return WellInformedPromptController(
    nudgeService: nudgeService,
    repository: repository,
  );
});

/// État affiché du prompt : `true` → rendre la carte ; `false`/loading →
/// `SizedBox.shrink()`. Invalidable pour forcer un refresh (ex. après submit
/// / skip, pour faire disparaître la carte sans setState externe).
final wellInformedShouldShowProvider = FutureProvider<bool>((ref) async {
  final controller = ref.watch(wellInformedPromptControllerProvider);
  return controller.shouldShow();
});
