import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/services/server_push_service.dart';

/// Coordinateur de l'amorce notif précoce (écran « Activer les rappels ? »
/// affiché à l'étape 3/4 de l'onboarding).
///
/// Séparé du widget pour être testable (le widget lit une instance via
/// [onboardingPushPrimingProvider], surchargeable en test).
///
/// Point CLÉ : accepter déclenche l'UNIQUE pop-up système et enregistre le
/// device (même sur session anonyme, avant la fin de l'onboarding) pour rendre
/// l'utilisateur joignable par une relance. Refuser ne déclenche AUCUNE demande
/// OS et ne touche JAMAIS `notif_modal_seen` (le gate de la modale d'activation
/// quotidienne) : le flag one-shot [seenKey] est distinct, si bien qu'un refus
/// ici ne consomme rien pour la demande quotidienne ultérieure.
class OnboardingPushPriming {
  const OnboardingPushPriming();

  /// Clé Hive (box `settings`) : amorce précoce vue une fois. DISTINCTE de
  /// `notif_modal_seen` — ne jamais fusionner les deux.
  static const seenKey = 'notif_early_priming_seen';

  Future<Box<dynamic>> _box() => Hive.openBox<dynamic>('settings');

  Future<bool> hasSeenPriming() async {
    final box = await _box();
    return box.get(seenKey, defaultValue: false) as bool;
  }

  Future<void> _markSeen() async {
    final box = await _box();
    await box.put(seenKey, true);
  }

  /// Accepte : déclenche la demande OS + enregistre le device. Renvoie `true`
  /// si le device est enregistré côté serveur (relance possible).
  Future<bool> acceptAndRegister() async {
    final registered = await ServerPushService.instance.initAndRegister();
    await _markSeen();
    return registered;
  }

  /// Refuse : marque l'amorce vue, sans aucun appel OS.
  Future<void> refuse() => _markSeen();
}

final onboardingPushPrimingProvider = Provider<OnboardingPushPriming>(
  (ref) => const OnboardingPushPriming(),
);
