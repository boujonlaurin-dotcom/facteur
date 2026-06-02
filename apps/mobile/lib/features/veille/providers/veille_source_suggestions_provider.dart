import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/veille_config_dto.dart';
import 'veille_repository_provider.dart';

typedef VeilleSourceSuggestionsQuery = ({
  String themeId,
  String themeLabel,
  String brief,
  String anglesKey,
  String keywordsKey,
});

/// Suggestions de sources niche pour le Step 3.
///
/// Une réponse 200 vide est un vide légitime. Les erreurs transport/API
/// remontent en `AsyncError`, ce qui permet à l'UI d'afficher un retry
/// distinct de l'état "aucune source".
final veilleSourceSuggestionsProvider = FutureProvider.autoDispose
    .family<List<VeilleSourceSuggestionDto>, VeilleSourceSuggestionsQuery>((
      ref,
      q,
    ) async {
      final repo = ref.watch(veilleRepositoryProvider);
      return repo.suggestSources(
        themeId: q.themeId,
        themeLabel: q.themeLabel,
        brief: q.brief,
        angles: _splitKey(q.anglesKey),
        keywords: _splitKey(q.keywordsKey),
      );
    });

List<String> _splitKey(String value) {
  if (value.trim().isEmpty) return const [];
  return value
      .split('|')
      .map((v) => v.trim())
      .where((v) => v.isNotEmpty)
      .toList();
}
