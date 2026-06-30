/// Modèles du système de feedback utilisateur (Epic 13).
library;

/// Statut de l'invitation au call qualitatif renvoyé par l'API.
class FeedbackInviteStatus {
  /// La modal doit-elle s'afficher ?
  final bool shouldShow;

  /// Segment d'activité ("returning" | "low_active" | "active") ou null.
  final String? segment;

  /// Raison du non-affichage (debug / analytics) ou null.
  final String? reason;

  const FeedbackInviteStatus({
    required this.shouldShow,
    this.segment,
    this.reason,
  });

  /// Valeur sûre par défaut : ne rien afficher.
  factory FeedbackInviteStatus.hidden() =>
      const FeedbackInviteStatus(shouldShow: false);

  factory FeedbackInviteStatus.fromJson(Map<String, dynamic> json) {
    return FeedbackInviteStatus(
      shouldShow: json['should_show'] as bool? ?? false,
      segment: json['segment'] as String?,
      reason: json['reason'] as String?,
    );
  }
}
