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
        _listEquals(other.selectedTopicIds, selectedTopicIds);
  }

  @override
  int get hashCode =>
      Object.hash(themeId, themeLabel, Object.hashAll(selectedTopicIds));

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
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
        VeilleTopicsSuggestionParams._listEquals(
          other.topicLabels,
          topicLabels,
        );
  }

  @override
  int get hashCode => Object.hash(themeId, Object.hashAll(topicLabels));
}

/// Suggestions topics LLM appelées au mount de l'étape 2. AutoDispose pour
/// libérer la mémoire dès que l'utilisateur quitte l'écran.
final veilleTopicSuggestionsProvider = FutureProvider.autoDispose
    .family<List<VeilleTopicSuggestion>, VeilleTopicsSuggestionParams>(
  (ref, params) async {
    final repo = ref.read(veilleRepositoryProvider);
    return repo.suggestTopics(
      themeId: params.themeId,
      themeLabel: params.themeLabel,
      selectedTopicIds: params.selectedTopicIds,
    );
  },
);

/// Suggestions sources LLM appelées au mount de l'étape 3.
final veilleSourceSuggestionsProvider = FutureProvider.autoDispose
    .family<VeilleSourceSuggestionsResponse, VeilleSourcesSuggestionParams>(
  (ref, params) async {
    final repo = ref.read(veilleRepositoryProvider);
    return repo.suggestSources(
      themeId: params.themeId,
      topicLabels: params.topicLabels,
    );
  },
);
