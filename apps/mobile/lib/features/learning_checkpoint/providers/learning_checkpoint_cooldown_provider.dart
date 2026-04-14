import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/learning_checkpoint_flags.dart';

/// Vrai si un `validate` ou `snooze` a eu lieu dans les dernières 24h.
/// Lu par le notifier principal pour gater l'affichage de la carte.
final learningCheckpointCooldownProvider = FutureProvider<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final lastActionAt =
      prefs.getInt(LearningCheckpointFlags.kLastActionAtKey);
  if (lastActionAt == null) return false;
  final elapsed = DateTime.now().millisecondsSinceEpoch - lastActionAt;
  return elapsed < LearningCheckpointFlags.cooldown.inMilliseconds;
});
