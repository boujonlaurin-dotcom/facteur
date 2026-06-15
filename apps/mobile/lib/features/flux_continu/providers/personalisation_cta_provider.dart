import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/nudges/nudge_coordinator.dart';
import '../../../core/nudges/nudge_ids.dart';

/// Éligibilité de la grande carte « Personnalise ton Essentiel ».
///
/// Le chargement reste masqué pour éviter un flash au démarrage. Un clic
/// retire la carte immédiatement, puis persiste un cooldown glissant de 30
/// jours via le registre unifié des nudges.
final personalisationCtaShouldShowProvider =
    AsyncNotifierProvider<PersonalisationCtaNotifier, bool>(
  PersonalisationCtaNotifier.new,
);

class PersonalisationCtaNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() {
    return ref.watch(nudgeServiceProvider).canShow(NudgeIds.personalisationCta);
  }

  Future<void> activate() async {
    state = const AsyncData(false);
    try {
      await ref
          .read(nudgeServiceProvider)
          .markShown(NudgeIds.personalisationCta);
    } catch (_) {
      // Best-effort : la carte reste retirée pour la session courante.
    }
  }
}
