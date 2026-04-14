import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Vrai si la carte « Construire ton flux » a déjà été affichée cette session.
///
/// v1 : une session = cycle de vie du process (cold start = reset).
/// Simplifié par rapport à la définition « > 30 min idle » de la spec ;
/// à raffiner en v2 si nécessaire.
final learningCheckpointShownThisSessionProvider =
    StateProvider<bool>((_) => false);
