import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/auth/auth_state.dart';
import '../models/alert_item.dart';
import '../models/alert_suggestion.dart';
import '../repositories/alerts_repository.dart';

final alertsRepositoryProvider = Provider<AlertsRepository>((ref) {
  return AlertsRepository(ref.watch(apiClientProvider));
});

/// Cloches actives de l'utilisateur — source unique du compteur « x / 5 »
/// affiché dans les réglages, sur la fiche source, la fiche sujet et l'écran
/// dédié. Le plafond est partagé entre sources et sujets.
final alertsProvider = AsyncNotifierProvider<AlertsNotifier, AlertsState>(() {
  return AlertsNotifier();
});

/// Cadence d'un sujet — pendant de `sourceProfileProvider`.
///
/// Chargée à l'ouverture de la fiche et pas dans la liste : elle coûte une
/// agrégation par sujet, et la liste en affiche des dizaines.
final topicFrequencyProvider =
    FutureProvider.family<TopicFrequency, String>((ref, topicId) async {
  return ref.watch(alertsRepositoryProvider).topicFrequency(topicId);
});

/// Suggestions de cibles à mettre sous cloche (story 30.6).
///
/// Dérivé de l'inventaire : il l'observe, donc toute pose ou tout retrait de
/// cloche le recalcule. C'est ce qui fait qu'une suggestion acceptée disparaît
/// du bloc au moment même où la cloche apparaît dans la liste, sans qu'aucun
/// des deux widgets n'ait à orchestrer l'autre.
/// `autoDispose` : les suggestions n'existent que pendant que « Mes alertes »
/// est à l'écran. Sans ça, chaque cloche posée depuis une fiche source, chaque
/// pull-to-refresh, chaque lecture de l'inventaire par la Tournée relancerait
/// un `GET /alerts/suggestions` pour un écran fermé, jusqu'à la fin de la vie
/// du process.
final alertSuggestionsProvider = AsyncNotifierProvider.autoDispose<
    AlertSuggestionsNotifier, AlertSuggestionsState>(() {
  return AlertSuggestionsNotifier();
});

class AlertSuggestionsNotifier
    extends AutoDisposeAsyncNotifier<AlertSuggestionsState> {
  @override
  FutureOr<AlertSuggestionsState> build() async {
    // On n'observe **que** les deux nombres réellement lus, via `select` :
    // `AlertsState` n'a pas d'`operator ==`, donc `watch` sur l'objet entier
    // referait un appel réseau à chaque rechargement de l'inventaire, y compris
    // quand rien de pertinent n'a bougé (un pull-to-refresh qui rend la même
    // chose, par exemple).
    final cap = ref.watch(alertsProvider.select((a) => a.valueOrNull?.cap));
    final activeCount =
        ref.watch(alertsProvider.select((a) => a.valueOrNull?.activeCount));
    // Tant que l'inventaire n'est pas là, il n'y a rien à proposer : l'appel
    // serait fait sans connaître le plafond et devrait être refait.
    if (cap == null || activeCount == null) return const AlertSuggestionsState();
    // Au plafond, on n'interroge même pas le serveur : l'écran explique déjà
    // le plafond dans son en-tête, et proposer un ajout impossible est pire
    // que ne rien proposer.
    if (activeCount >= cap) {
      return AlertSuggestionsState(
        cap: cap,
        activeCount: activeCount,
        atCap: true,
      );
    }
    return ref.read(alertsRepositoryProvider).listSuggestions();
  }

  /// Écarte une suggestion : retrait local immédiat, mémorisation serveur.
  ///
  /// L'ordre compte. La ligne disparaît au frame suivant sans attendre le
  /// réseau ; le serveur, lui, s'en souvient pour que la suggestion ne revienne
  /// pas demain.
  Future<void> dismiss(AlertSuggestion suggestion) async {
    forget(suggestion.targetId);
    await ref
        .read(alertsRepositoryProvider)
        .dismissSuggestion(suggestion.kind, suggestion.targetId);
  }

  /// Retrait local seul, après une pose réussie : `alertsProvider` va de toute
  /// façon se recharger et relancer `build()`, ce retrait ne sert qu'à éviter
  /// le clignotement d'une ligne déjà acceptée.
  void forget(String targetId) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.without(targetId));
  }
}

class AlertsNotifier extends AsyncNotifier<AlertsState> {
  @override
  FutureOr<AlertsState> build() async {
    final authState = ref.watch(authStateProvider);
    if (!authState.isAuthenticated) return const AlertsState();
    return ref.read(alertsRepositoryProvider).listAlerts();
  }

  /// Pose ou retire la cloche sur [sourceId].
  ///
  /// Pas d'optimisme ici : le serveur est seul juge du plafond, et un toggle
  /// qui s'allume puis se rétracte est pire qu'un toggle qui met 200 ms.
  /// [AlertCapReachedException] remonte à l'appelant, qui porte la copy.
  Future<void> setAlert(
    String sourceId,
    bool enabled, {
    bool filtered = false,
  }) async {
    final repo = ref.read(alertsRepositoryProvider);
    await repo.setAlert(sourceId, enabled, filtered: filtered);
    await _reload(repo);
  }

  /// Même geste, sur un sujet suivi.
  Future<void> setTopicAlert(
    String topicId,
    bool enabled, {
    bool filtered = false,
  }) async {
    final repo = ref.read(alertsRepositoryProvider);
    await repo.setTopicAlert(topicId, enabled, filtered: filtered);
    await _reload(repo);
  }

  Future<void> refresh() async {
    await _reload(ref.read(alertsRepositoryProvider));
  }

  /// La réponse du toggle ne porte que le compteur : on relit la liste complète
  /// pour que l'écran « Mes alertes » et la section Tournée soient justes du
  /// même coup.
  Future<void> _reload(AlertsRepository repo) async {
    state = AsyncData(await repo.listAlerts());
  }

  /// Cloche posée sur [targetId] (source ou sujet), état connu seulement.
  bool isEnabled(String targetId) {
    return state.valueOrNull?.items.any((i) => i.sourceId == targetId) ?? false;
  }
}
