/// Identifiants stables du tour guidé.
///
/// Le flag « déjà vu » est persisté sous `nudge.<id>.seen.<userId>` — on réutilise
/// le namespace `nudge.` et la sémantique **scopée user** de `NudgeStorage`
/// (`isSeenForUser` / `markSeenForUser`) pour qu'un second compte sur le même
/// appareil revoie le tour.
class TourIds {
  TourIds._();

  /// Tour guidé post-onboarding (5 étapes, joué une seule fois).
  static const guidedTour = 'guided_tour';
}
