import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/veille_delivery.dart';
import 'veille_repository_provider.dart';

/// AsyncNotifier load-on-enter pour la liste des livraisons (limit=20).
///
/// Refresh = `ref.invalidate(veilleDeliveriesProvider)` (pull-to-refresh côté
/// UI). Pas de cache disque, pas de stale-fallback.
class VeilleDeliveriesNotifier
    extends AsyncNotifier<List<VeilleDeliveryListItem>> {
  @override
  Future<List<VeilleDeliveryListItem>> build() async {
    final repo = ref.read(veilleRepositoryProvider);
    return repo.listDeliveries();
  }
}

final veilleDeliveriesProvider = AsyncNotifierProvider<
    VeilleDeliveriesNotifier, List<VeilleDeliveryListItem>>(
  VeilleDeliveriesNotifier.new,
);

/// Détail d'une livraison particulière. AutoDispose family : la mémoire est
/// libérée dès qu'on quitte l'écran de détail.
final veilleDeliveryProvider = FutureProvider.autoDispose
    .family<VeilleDeliveryResponse, String>(
  (ref, deliveryId) async {
    final repo = ref.read(veilleRepositoryProvider);
    return repo.getDelivery(deliveryId);
  },
);

/// Dernière livraison (limit 1) — utilisé par le dashboard pour gating la CTA
/// « Lancer ma première veille » sans tirer la liste de 20.
class VeilleLastDeliveryNotifier
    extends AsyncNotifier<VeilleDeliveryListItem?> {
  @override
  Future<VeilleDeliveryListItem?> build() async {
    final repo = ref.read(veilleRepositoryProvider);
    final list = await repo.listDeliveries(limit: 1);
    return list.isEmpty ? null : list.first;
  }
}

final veilleLastDeliveryProvider = AsyncNotifierProvider<
    VeilleLastDeliveryNotifier, VeilleDeliveryListItem?>(
  VeilleLastDeliveryNotifier.new,
);
