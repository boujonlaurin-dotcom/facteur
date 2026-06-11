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
    prev = cur;
  }
  return container.read(fluxContinuProvider).requireValue;
}
