import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/grille_models.dart';
import 'grille_provider.dart';

/// Classement du jour. `autoDispose` → rechargé à chaque ouverture de l'écran.
///
/// Lève [GrilleGameInProgressException] (409) tant que la partie n'est pas
/// terminée : l'écran de classement n'est atteignable qu'après le Résultat.
final grilleLeaderboardProvider =
    FutureProvider.autoDispose<GrilleLeaderboardResponse>((ref) async {
  final repo = ref.watch(grilleRepositoryProvider);
  return repo.getLeaderboard();
});
