import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../onboarding/data/available_subtopics.dart';
import '../models/veille_config.dart';

/// Cache léger pour `/users/algorithm-profile` : un seul fetch partagé
/// entre les différentes valeurs de `themeSlug` du
/// [veillePresetTopicsProvider].
final _userSubtopicSlugsProvider = FutureProvider<Set<String>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  try {
    final response =
        await apiClient.dio.get<dynamic>('users/algorithm-profile');
    final body = response.data as Map<String, dynamic>;
    final weights = body['subtopic_weights'];
    if (weights is Map) {
      return weights.keys.map((k) => k.toString()).toSet();
    }
    return const <String>{};
  } on DioException {
    return const <String>{};
  }
});

/// Pour un thème Facteur (`themeSlug`), retourne tous les sous-sujets
/// disponibles dans `AvailableSubtopics.byTheme[themeSlug]`. Les sujets
/// déjà suivis par le user dans l'app sont placés en tête de liste et
/// marqués « Suivi dans l'app » — sans pré-sélection : on laisse au user
/// le choix actif des angles à mettre dans sa veille.
///
/// Renvoie `[]` si le thème n'a pas d'entrée subtopics — Step 2 LLM
/// compense alors avec ses propres suggestions.
final veillePresetTopicsProvider =
    FutureProvider.family<List<VeilleTopic>, String>((ref, themeSlug) async {
  final options = AvailableSubtopics.byTheme[themeSlug];
  if (options == null || options.isEmpty) return const <VeilleTopic>[];

  final userSubtopicSlugs = await ref.watch(_userSubtopicSlugsProvider.future);

  final ranked = <({bool isUserPicked, VeilleTopic topic})>[];
  for (final opt in options) {
    final isUserPicked = userSubtopicSlugs.contains(opt.slug);
    ranked.add((
      isUserPicked: isUserPicked,
      topic: VeilleTopic(
        id: opt.slug,
        label: '${opt.emoji} ${opt.label}',
        reason: isUserPicked
            ? 'Suivi dans l\'app'
            : (opt.isPopular
                ? 'angle populaire pour ce thème'
                : 'proposé pour ce thème'),
      ),
    ));
  }

  // Stable sort : suivis en haut, ordre original conservé dans chaque groupe.
  ranked.sort((a, b) {
    if (a.isUserPicked == b.isUserPicked) return 0;
    return a.isUserPicked ? -1 : 1;
  });

  return ranked.map((r) => r.topic).toList();
});
