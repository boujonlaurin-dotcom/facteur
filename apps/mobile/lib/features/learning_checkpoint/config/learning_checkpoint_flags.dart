/// Flags statiques pour la feature « Construire ton flux » (Learning Checkpoint).
///
/// Aucun remote config n'est disponible dans le projet v1 : ces valeurs sont
/// compilées. Un override local via SharedPreferences
/// (`learning_checkpoint_force_disabled`) est exposé pour le QA.
class LearningCheckpointFlags {
  const LearningCheckpointFlags._();

  /// Kill-switch local. Passer à `false` + hotfix release pour désactiver.
  static const bool enabled = true;

  /// Seuils de gating (exposés pour tests).
  static const int minProposals = 3;
  static const double minSignalStrength = 0.6;
  static const Duration cooldown = Duration(hours: 24);
  static const int maxProposalsDisplayed = 5;

  /// Position dans la `SliverList` du feed.
  static const int feedInjectionPosition = 3;

  /// Clés SharedPreferences.
  static const String kLastActionAtKey =
      'learning_checkpoint_last_action_at';
  static const String kForceDisabledKey =
      'learning_checkpoint_force_disabled';
}
