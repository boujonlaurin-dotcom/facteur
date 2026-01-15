import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../sources/repositories/sources_repository.dart';
import '../../../core/api/providers.dart';

/// Provider qui calcule le biais politique de l'utilisateur
/// basé sur les sources qu'il suit (même logique que le backend)
final userBiasProvider = FutureProvider<String?>((ref) async {
  try {
    final apiClient = ref.watch(apiClientProvider);
    final repository = SourcesRepository(apiClient);

    // Récupérer toutes les sources et filtrer celles de confiance
    final allSources = await repository.getAllSources();
    final sources = allSources.where((s) => s.isTrusted).toList();

    if (sources.isEmpty) return null;

    // Calculer le score de biais (même logique que _calculate_user_bias dans le backend)
    int score = 0;
    for (final source in sources) {
      switch (source.biasStance) {
        case 'left':
        case 'center-left':
          score -= 1;
          break;
        case 'right':
        case 'center-right':
          score += 1;
          break;
      }
    }

    // Retourner le biais dominant
    if (score < 0) {
      return 'left';
    } else if (score > 0) {
      return 'right';
    } else {
      return 'center';
    }
  } catch (e) {
    // En cas d'erreur, retourner null (description par défaut sera utilisée)
    return null;
  }
});
