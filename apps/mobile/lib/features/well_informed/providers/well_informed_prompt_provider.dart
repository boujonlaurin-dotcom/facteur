import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/nudges/nudge_coordinator.dart';
import '../../../core/nudges/nudge_ids.dart';
import '../../../core/nudges/nudge_service.dart';
import '../data/well_informed_repository.dart';

/// Clé SharedPreferences portant le timestamp de la DERNIÈRE soumission
/// (distincte de `nudge.well_informed_poll.lastShown` utilisée par le service
/// nudges pour tout "shown" — y compris skip). Permet d'imposer 14j après
/// réponse même si le nudge lui-même a un cooldown de 5j (pour le skip).
const String kWellInformedLastSubmittedPrefsKey =
    'well_informed_poll_last_submitted_at_ms';

const Duration kWellInformedSubmittedCooldown = Duration(days: 14);

/// Coordinateur métier du prompt "bien informé".
///
/// - `shouldShow()` : vrai si aucune soumission < 14j ET le nudge (cooldown 5j
///   configuré dans NudgeRegistry) autorise l'affichage.
/// - `recordShown()` : enregistre un shown (sert pour la cooldown skip).
/// - `submit()` : POST la note + marque la soumission + avance le cooldown
///   long (14j).
/// - `skip()` : marque un shown (cooldown court 5j), pas de POST.
class WellInformedPromptController {
  WellInformedPromptController({
    required NudgeService nudgeService,
    required WellInformedRepository repository,
    DateTime Function()? clock,
    Future<SharedPreferences> Function()? prefs,
  })  : _nudgeService = nudgeService,
        _repository = repository,
        _clock = clock ?? DateTime.now,
        _prefsFactory = prefs ?? SharedPreferences.getInstance;

  final NudgeService _nudgeService;
  final WellInformedRepository _repository;
  final DateTime Function() _clock;
  final Future<SharedPreferences> Function() _prefsFactory;

  Future<bool> shouldShow() async {
    final prefs = await _prefsFactory();
    final submittedMs = prefs.getInt(kWellInformedLastSubmittedPrefsKey);
    if (submittedMs != null) {
      final last = DateTime.fromMillisecondsSinceEpoch(submittedMs);
      if (_clock().difference(last) < kWellInformedSubmittedCooldown) {
        return false;
      }
    }
    return _nudgeService.canShow(NudgeIds.wellInformedPoll);
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
