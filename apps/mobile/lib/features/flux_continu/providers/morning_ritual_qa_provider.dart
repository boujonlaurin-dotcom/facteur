import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Override **QA only** (visible uniquement en staging/dev, cf. `profile_screen`)
/// : force le rituel matinal à considérer l'édition « pas prête » pour valider
/// l'état B (bail vers le feed) sans dépendre d'un vrai réseau froid.
///
/// Non persisté : remis à `false` à chaque cold-start. Aucun effet en prod où
/// le bloc QA qui le bascule n'est jamais monté.
final debugForceMorningRitualNotReadyProvider = StateProvider<bool>(
  (ref) => false,
);
