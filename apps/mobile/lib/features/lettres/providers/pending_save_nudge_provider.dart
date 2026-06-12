import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Intent en attente : quand l'utilisateur tape l'action « Sauvegarder 3
/// articles » depuis une lettre, on bascule sur Flâner et on arme ce flag.
/// Le 1er article ouvert le consomme pour « pop » le bouton Sauvegarder
/// (bounce + bulle nudge), puis le remet à false (one-shot).
final pendingSaveNudgeProvider = StateProvider<bool>((ref) => false);
