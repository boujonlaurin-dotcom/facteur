import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Phase de chargement progressif du [FeedScreen].
///
/// Permet de réduire le burst de requêtes au mount (~8 providers en parallèle
/// historiquement) en déclenchant les `ref.watch` non-critiques par vagues :
///
/// - [critical] (t=0) : digest + feed page 1 uniquement
/// - [postFrame] (post-first-frame) : chrome du feed (tab counts, custom topics,
///   user sources)
/// - [idle] (post 800ms OU dès que feedProvider a `AsyncData`) : reste (streak,
///   savedSummary, pepites, hints, sereinToggle, appUpdate, etc.)
///
/// L'ordre des cas est significatif (utilisé par [FeedLoadPhaseX.hasReachedX]
/// via `index`) — ne pas réordonner.
enum FeedLoadPhase {
  critical,
  postFrame,
  idle,
}

extension FeedLoadPhaseX on FeedLoadPhase {
  bool get hasReachedPostFrame => index >= FeedLoadPhase.postFrame.index;
  bool get hasReachedIdle => index >= FeedLoadPhase.idle.index;
}

final feedLoadPhaseProvider = StateProvider<FeedLoadPhase>((_) {
  return FeedLoadPhase.critical;
});

/// Avance la phase à [target] uniquement si la phase courante est inférieure
/// (transitions monotoniques). Idempotent.
void advanceFeedLoadPhase(WidgetRef ref, FeedLoadPhase target) {
  final notifier = ref.read(feedLoadPhaseProvider.notifier);
  if (target.index > notifier.state.index) {
    notifier.state = target;
  }
}
