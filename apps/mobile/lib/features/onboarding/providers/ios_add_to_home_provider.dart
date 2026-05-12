import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/nudges/nudge_coordinator.dart';
import '../../../core/nudges/nudge_ids.dart';
import '../../../core/nudges/nudge_service.dart';
import '../../../core/web/ios_safari_install.dart';

/// Une fois la modal "Ajouter à l'écran d'accueil" affichée dans la session,
/// on ne la déclenche pas une seconde fois avant le prochain cold start.
final iosAddToHomeConsumedThisSessionProvider =
    StateProvider<bool>((_) => false);

/// Contrôleur de visibilité de la modal iOS "Ajouter à l'écran d'accueil".
///
/// Deux portes :
///  - `isSeen` (permanent) — l'utilisateur a confirmé "C'est fait".
///  - `canShow` (cooldown 7j) — l'utilisateur a fermé via "Plus tard".
/// On combine les deux car `canShow` pour une fréquence `cooldown` ignore
/// `isSeen`. Sans `isSeen` la modal reviendrait 7j après le "C'est fait".
class IosAddToHomeController {
  IosAddToHomeController({required NudgeService nudgeService})
      : _nudgeService = nudgeService;

  final NudgeService _nudgeService;

  Future<bool> shouldShow() async {
    if (!isIosSafariNonStandalone()) return false;
    if (await _nudgeService.isSeen(NudgeIds.iosAddToHome)) return false;
    return _nudgeService.canShow(NudgeIds.iosAddToHome);
  }

  /// L'utilisateur a confirmé l'installation — on ne re-montre plus jamais.
  Future<void> markConfirmed() async {
    await _nudgeService.markSeen(NudgeIds.iosAddToHome);
  }

  /// L'utilisateur a snoozé — on attend 7j (cooldown du nudge) avant de
  /// re-proposer.
  Future<void> markDismissed() async {
    await _nudgeService.markShown(NudgeIds.iosAddToHome);
  }
}

final iosAddToHomeControllerProvider = Provider<IosAddToHomeController>((ref) {
  return IosAddToHomeController(
    nudgeService: ref.watch(nudgeServiceProvider),
  );
});

/// Provider async consommé par `firstImpressionSlotProvider`. Renvoie
/// `false` par défaut tant que le check storage n'a pas répondu — l'orchestrateur
/// laissera passer un autre slot, ce qui est OK : la modal s'affichera au
/// rebuild suivant (le watch ré-évalue dès que l'AsyncValue passe à `data`).
final iosAddToHomeShouldShowProvider = FutureProvider<bool>((ref) async {
  final controller = ref.watch(iosAddToHomeControllerProvider);
  return controller.shouldShow();
});
