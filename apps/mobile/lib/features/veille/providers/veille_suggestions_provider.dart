import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/veille_suggestion.dart';
import 'veille_repository_provider.dart';

/// Param du FutureProvider topics — `theme_id`, `theme_label`, et la liste
/// `selected_topic_ids` (utilisée par le LLM pour exclure ce qui est déjà
/// dans la sélection user).
@immutable
class VeilleTopicsSuggestionParams {
  final String themeId;
  final String themeLabel;
  final List<String> selectedTopicIds;

  const VeilleTopicsSuggestionParams({
    required this.themeId,
    required this.themeLabel,
    required this.selectedTopicIds,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VeilleTopicsSuggestionParams &&
        other.themeId == themeId &&
        other.themeLabel == themeLabel &&
        listEquals(other.selectedTopicIds, selectedTopicIds);
  }

  @override
  int get hashCode =>
      Object.hash(themeId, themeLabel, Object.hashAll(selectedTopicIds));
}

@immutable
class VeilleSourcesSuggestionParams {
  final String themeId;
  final List<String> topicLabels;

  const VeilleSourcesSuggestionParams({
    required this.themeId,
    required this.topicLabels,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VeilleSourcesSuggestionParams &&
        other.themeId == themeId &&
        listEquals(other.topicLabels, topicLabels);
  }

  @override
  int get hashCode => Object.hash(themeId, Object.hashAll(topicLabels));
}

// ─── Topics ──────────────────────────────────────────────────────────────────

/// StateNotifier des suggestions topics (Step 2). Charge initialement via
/// `/suggestions/topics`, puis expose `refreshKeepingChecked(checkedIds)`
/// pour ne remplacer **que les items non cochés** : les items cochés
/// restent en tête de liste, les nouvelles suggestions du LLM remplissent
/// les emplacements libres (en excluant les ids déjà affichés pour pousser
/// le LLM à varier ses propositions).
class VeilleTopicsSuggestionsNotifier
    extends StateNotifier<AsyncValue<List<VeilleTopicSuggestion>>> {
  final Ref _ref;
  final VeilleTopicsSuggestionParams _params;
  List<VeilleTopicSuggestion> _kept = const [];

  VeilleTopicsSuggestionsNotifier(this._ref, this._params)
      : super(const AsyncValue.loading()) {
    _fetch(excludeIds: const []);
  }

  Future<void> _fetch({required List<String> excludeIds}) async {
    state = const AsyncValue.loading();
    try {
      final repo = _ref.read(veilleRepositoryProvider);
      final items = await repo.suggestTopics(
        themeId: _params.themeId,
        themeLabel: _params.themeLabel,
        selectedTopicIds: _params.selectedTopicIds,
        excludeTopicIds: excludeIds,
      );
      final keptIds = _kept.map((t) => t.topicId).toSet();
      final fresh = items.where((t) => !keptIds.contains(t.topicId)).toList();
      state = AsyncValue.data([..._kept, ...fresh]);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Remplace les suggestions non cochées par de nouvelles, en conservant
  /// les items cochés (`checkedIds`). Les ids actuellement affichés sont
  /// exclus du prochain appel LLM pour ne pas re-proposer la même chose.
  Future<void> refreshKeepingChecked(Set<String> checkedIds) async {
    final current = state.valueOrNull ?? const <VeilleTopicSuggestion>[];
    _kept = current.where((t) => checkedIds.contains(t.topicId)).toList();
    final excludeIds = current.map((t) => t.topicId).toList();
    await _fetch(excludeIds: excludeIds);
  }
}

final veilleTopicSuggestionsProvider = StateNotifierProvider.autoDispose
    .family<VeilleTopicsSuggestionsNotifier,
        AsyncValue<List<VeilleTopicSuggestion>>, VeilleTopicsSuggestionParams>(
  (ref, params) => VeilleTopicsSuggestionsNotifier(ref, params),
);

// ─── Sources ─────────────────────────────────────────────────────────────────

/// StateNotifier des suggestions sources (Step 3). Même logique de
/// remplacement « non-cochés uniquement » que les topics, mais appliquée
/// uniquement aux **niches** : les `followed` viennent du catalogue de
/// l'utilisateur, ils ne sont pas regénérés par le LLM.
class VeilleSourcesSuggestionsNotifier
    extends StateNotifier<AsyncValue<VeilleSourceSuggestionsResponse>> {
  final Ref _ref;
  final VeilleSourcesSuggestionParams _params;
  List<VeilleSourceSuggestion> _keptNiche = const [];

  VeilleSourcesSuggestionsNotifier(this._ref, this._params)
      : super(const AsyncValue.loading()) {
    _fetch(excludeIds: const []);
  }

  Future<void> _fetch({required List<String> excludeIds}) async {
    state = const AsyncValue.loading();
    try {
      final repo = _ref.read(veilleRepositoryProvider);
      final resp = await repo.suggestSources(
        themeId: _params.themeId,
        topicLabels: _params.topicLabels,
        excludeSourceIds: excludeIds,
      );
      final keptIds = _keptNiche.map((s) => s.sourceId).toSet();
      final freshNiche =
          resp.niche.where((s) => !keptIds.contains(s.sourceId)).toList();
      state = AsyncValue.data(
        VeilleSourceSuggestionsResponse(
          followed: resp.followed,
          niche: [..._keptNiche, ...freshNiche],
        ),
      );
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Remplace les niches non cochées par de nouvelles. Les niches cochées
  /// (présentes dans `checkedNicheIds`) sont conservées ; les ids des
  /// niches actuellement affichées sont passés en `excludeSourceIds`.
  Future<void> refreshKeepingChecked(Set<String> checkedNicheIds) async {
    final current = state.valueOrNull;
    final currentNiche = current?.niche ?? const <VeilleSourceSuggestion>[];
    _keptNiche =
        currentNiche.where((s) => checkedNicheIds.contains(s.sourceId)).toList();
    final excludeIds = currentNiche.map((s) => s.sourceId).toList();
    await _fetch(excludeIds: excludeIds);
  }
}

final veilleSourceSuggestionsProvider = StateNotifierProvider.autoDispose
    .family<VeilleSourcesSuggestionsNotifier,
        AsyncValue<VeilleSourceSuggestionsResponse>,
        VeilleSourcesSuggestionParams>(
  (ref, params) => VeilleSourcesSuggestionsNotifier(ref, params),
);
