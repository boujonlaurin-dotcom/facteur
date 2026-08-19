import 'package:facteur/features/flux_continu/models/flux_continu_models.dart';
import 'package:facteur/features/flux_continu/providers/flux_continu_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Démarrage matinal : `build()` émet désormais de façon **progressive**
/// (squelette → base-only → complet) ; le `.future` du provider se résout à la
/// PREMIÈRE émission. Ce helper draine la file jusqu'à ce que l'état complet
/// (non squelette) se stabilise, puis le renvoie — remplace l'ancien
/// `container.read(fluxContinuProvider.future)` qui donnait l'état complet
/// avant l'introduction du rendu progressif.
Future<FluxContinuState> settle(ProviderContainer container) async {
  container.read(fluxContinuProvider);
  FluxContinuState? prev;
  for (var i = 0; i < 60; i++) {
    await pumpEventQueue(times: 3);
    final cur = container.read(fluxContinuProvider).valueOrNull;
    if (cur != null && !cur.isSkeleton && identical(cur, prev)) break;
    final progressed = cur != null && !identical(cur, prev);
    prev = cur;
    // Lot cold start (B1) — le bootstrap contient désormais de vrais timers
    // (tête d'avance héros 600 ms, attente bornée ~2 s des prérequis de
    // coquilles) : drainer la file d'événements ne suffit plus, il faut aussi
    // laisser s'écouler du temps réel (budget 60 × 50 ms = 3 s). On ne dort
    // que quand l'état **stagne** (on attend un timer réel) — tant que les
    // émissions progressent, on re-draine immédiatement.
    if (!progressed) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
  return container.read(fluxContinuProvider).requireValue;
}
