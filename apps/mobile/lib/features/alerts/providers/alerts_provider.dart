import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/auth/auth_state.dart';
import '../models/alert_item.dart';
import '../repositories/alerts_repository.dart';

final alertsRepositoryProvider = Provider<AlertsRepository>((ref) {
  return AlertsRepository(ref.watch(apiClientProvider));
});

/// Cloches actives de l'utilisateur — source unique du compteur « x / 5 »
/// affiché dans les réglages, sur la fiche source et dans l'écran dédié.
final alertsProvider = AsyncNotifierProvider<AlertsNotifier, AlertsState>(() {
  return AlertsNotifier();
});

class AlertsNotifier extends AsyncNotifier<AlertsState> {
  @override
  FutureOr<AlertsState> build() async {
    final authState = ref.watch(authStateProvider);
    if (!authState.isAuthenticated) return const AlertsState();
    return ref.read(alertsRepositoryProvider).listAlerts();
  }

  /// Pose ou retire la cloche sur [sourceId].
  ///
  /// Pas d'optimisme ici : le serveur est seul juge du plafond et de la
  /// rareté, et un toggle qui s'allume puis se rétracte est pire qu'un toggle
  /// qui met 200 ms. Les exceptions typées ([AlertCapReachedException],
  /// [SourceNotRareException]) remontent à l'appelant, qui porte la copy.
  Future<void> setAlert(String sourceId, bool enabled) async {
    final repo = ref.read(alertsRepositoryProvider);
    await repo.setAlert(sourceId, enabled);
    // La réponse du toggle ne porte que le compteur : on relit la liste
    // complète pour que l'écran « Mes alertes » et la section Tournée soient
    // justes du même coup.
    state = AsyncData(await repo.listAlerts());
  }

  Future<void> refresh() async {
    state = AsyncData(await ref.read(alertsRepositoryProvider).listAlerts());
  }

  /// Vrai si une cloche est posée sur [sourceId] (état connu seulement).
  bool isEnabled(String sourceId) {
    return state.valueOrNull?.items.any((i) => i.sourceId == sourceId) ?? false;
  }
}
