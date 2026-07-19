import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Signal « joue le pulse maintenant » pour une carte donnée. Le [nonce]
/// change à chaque déclenchement pour que deux pulses successifs sur la même
/// carte soient bien distingués (cf. `AutoGrowPulse.didUpdateWidget`).
class AutoGrowSignal {
  const AutoGrowSignal({required this.contentId, required this.nonce});

  final String contentId;
  final int nonce;

  @override
  bool operator ==(Object other) =>
      other is AutoGrowSignal &&
      other.contentId == contentId &&
      other.nonce == nonce;

  @override
  int get hashCode => Object.hash(contentId, nonce);
}

/// Ensemble des `contentId` de cartes Flux/Essentiel actuellement **visibles**
/// à l'écran (seuil `visibleFraction >= 0.9`, même convention que
/// `feed_carousel.dart`). Alimenté par le `VisibilityDetector` de chaque tuile
/// et lu par le timer du nudge (`flux_continu_screen.dart`) pour tirer un
/// candidat.
final visibleFluxContentIdsProvider = StateProvider<Set<String>>(
  (ref) => <String>{},
);

/// Signal courant du nudge auto-grow. `null` = aucun pulse en attente. Chaque
/// tuile dérive son `playToken` via
/// `select((s) => s?.contentId == id ? s!.nonce : null)`.
final autoGrowNudgeSignalProvider = StateProvider<AutoGrowSignal?>(
  (ref) => null,
);
