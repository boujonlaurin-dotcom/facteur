import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import 'personalized_filters_provider.dart';

/// Mapping des thèmes vers leurs emojis et labels FR.
const _themeMetadata = <String, ({String label, String emoji})>{
  'tech': (label: 'Tech', emoji: '💻'),
  'science': (label: 'Science', emoji: '🔬'),
  'culture': (label: 'Culture', emoji: '🎨'),
  'society': (label: 'Société', emoji: '👥'),
  'international': (label: 'Géopo', emoji: '🌍'),
  'economy': (label: 'Éco', emoji: '💰'),
  'politics': (label: 'Politique', emoji: '🏛️'),
  'environment': (label: 'Environnement', emoji: '🌿'),
  'health': (label: 'Santé', emoji: '🏥'),
  'sports': (label: 'Sport', emoji: '⚽'),
  'education': (label: 'Éducation', emoji: '📚'),
  'business': (label: 'Business', emoji: '💼'),
  'entertainment': (label: 'Divertissement', emoji: '🎬'),
  'philosophy': (label: 'Philo', emoji: '🤔'),
  'history': (label: 'Histoire', emoji: '📜'),
  'crypto': (label: 'Crypto', emoji: '₿'),
  'ai': (label: 'IA', emoji: '🤖'),
};

/// Provider qui récupère les thèmes de l'utilisateur depuis l'API et
/// les convertit en FilterConfig pour le FilterBar.
final themeFiltersProvider =
    FutureProvider<List<FilterConfig>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);

  try {
    final response = await apiClient.dio.get<dynamic>('users/top-themes');

    if (response.statusCode == 200 && response.data != null) {
      final themes = response.data as List<dynamic>;

      return themes.map<FilterConfig>((t) {
        final slug = t['interest_slug'] as String;
        final meta = _themeMetadata[slug];
        final label = meta != null ? meta.label : slug;
        final description = meta != null
            ? 'Contenus ${meta.label} de vos sources'
            : 'Contenus $slug de vos sources';

        return FilterConfig(
          key: slug,
          label: label,
          description: description,
        );
      }).toList();
    }
  } catch (_) {
    // Fallback silencieux — pas de thèmes affichés si l'API échoue
  }

  return [];
});
