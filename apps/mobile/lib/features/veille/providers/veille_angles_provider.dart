import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/veille_config_dto.dart';
import 'veille_repository_provider.dart';

/// Clé de cache de [veilleAnglesProvider] : thème + brief pilotent la
/// suggestion LLM (le backend cache sur le triplet `theme_id`/`theme_label`/
/// `brief` pendant 24 h).
typedef VeilleAnglesQuery = ({String themeId, String themeLabel, String brief});

/// Suggestion d'angles LLM pour le Step 2 (titre + grappe de mots-clés).
///
/// Délègue à `VeilleRepository.suggestAngles`, qui retourne `[]` en cas
/// d'erreur/timeout — l'UI retombe alors sur les preset topics statiques,
/// donc aucune régression si le LLM est KO. `autoDispose` : la suggestion est
/// re-déclenchée à chaque entrée dans le Step 2 (le cache backend absorbe le
/// coût des appels répétés).
final veilleAnglesProvider = FutureProvider.autoDispose
    .family<List<VeilleAngleSuggestionDto>, VeilleAnglesQuery>((ref, q) async {
  final repo = ref.watch(veilleRepositoryProvider);
  return repo.suggestAngles(
    themeId: q.themeId,
    themeLabel: q.themeLabel,
    brief: q.brief,
  );
});
