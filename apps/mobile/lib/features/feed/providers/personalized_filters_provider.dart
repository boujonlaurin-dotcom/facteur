import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/constants.dart';
import '../../onboarding/providers/onboarding_provider.dart';

/// Configuration d'un filtre pour le feed
class FilterConfig {
  final String key;
  final String label;
  final String description; // Description courte (sous le chip)
  final bool isVisible;
  final List<String>? filteredKeywords; // Mots-clés filtrés si applicable

  const FilterConfig({
    required this.key,
    required this.label,
    required this.description,
    this.isVisible = true,
    this.filteredKeywords,
  });
}

/// Provider qui retourne la liste des filtres ordonnée et personnalisée selon le profil
final personalizedFiltersProvider = Provider<List<FilterConfig>>((ref) {
  // On écoute le userProfileProvider pour avoir les dernières réponses
  // Note: userProfileProvider peut wrapper les données mais ici on accède direct aux réponses via onboardingProvider
  // pour simplifier si userProfileProvider n'expose pas tout directement.
  // Cependant, onboardingProvider est la source de vérité post-onboarding local,
  // et userProfileProvider est souvent sync avec le backend.
  // Vérifions d'abord onboardingProvider car c'est là que sont les réponses brutes typées.
  final onboardingState = ref.watch(onboardingProvider);
  final answers = onboardingState.answers;

  // Configuration de base (Ordre par défaut)
  // 1. Breaking (Dernières news)
  // 2. Inspiration (Rester serein)
  // 3. Perspectives (Changer de perspective)
  // 4. Deep Dive (Longs formats)

  final filters = [
    const FilterConfig(
      key: 'breaking',
      label: 'Dernières news',
      description: 'Les actus chaudes des dernières 12h',
    ),
    const FilterConfig(
      key: 'inspiration',
      label: 'Rester serein',
      description: 'Sans thèmes anxiogènes',
      filteredKeywords: FeedConstants.defaultFilteredKeywords,
    ),
    const FilterConfig(
      key: 'perspectives',
      label: 'Changer de perspective',
      description:
          'Changez d\'angle de vue pour enrichir votre opinion', // Sera dynamique dans l'UI via getPerspectivesDescription
    ),
    const FilterConfig(
      key: 'deep_dive',
      label: 'Longs formats',
      description: 'Des formats longs pour comprendre',
    ),
  ];

  // Logique de personnalisation

  // 1. "Longs formats" en premier si Objectif = Learn
  // (Note: OnboardingAnswers.objective -> 'learn', 'culture', 'work'...)
  if (answers.objective == 'learn' || answers.approach == 'detailed') {
    _moveFilterToFront(filters, 'deep_dive');
  }

  // 2. "Dernières news" en premier si Style = Decisive
  if (answers.responseStyle == 'decisive') {
    _moveFilterToFront(filters, 'breaking');
  }

  // 3. "Rester serein" en premier si Style = Nuanced ou PersonalGoal = 'mental_health' (si existe)
  // ou si Perspective = 'big_picture' (hypothèse: préfère le recul)
  if (answers.responseStyle == 'nuanced' ||
      answers.perspective == 'big_picture') {
    _moveFilterToFront(filters, 'inspiration');
  }

  return filters;
});

void _moveFilterToFront(List<FilterConfig> filters, String key) {
  final index = filters.indexWhere((f) => f.key == key);
  if (index != -1) {
    final item = filters.removeAt(index);
    filters.insert(0, item);
  }
}
