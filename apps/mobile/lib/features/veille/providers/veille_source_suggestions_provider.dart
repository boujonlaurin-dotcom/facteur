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
/// Le repo renvoie `[]` en cas d'erreur/timeout ; l'UI affiche alors un état
/// vide avec un bouton qui invalide ce provider pour relancer la pipeline.
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
