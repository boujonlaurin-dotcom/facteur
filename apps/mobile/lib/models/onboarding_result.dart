import 'user_profile.dart';

/// Types d'erreur possibles lors de la sauvegarde de l'onboarding
enum ErrorType {
  /// Erreur réseau (timeout, connexion perdue)
  network,

  /// Erreur d'authentification (token invalide/expiré)
  auth,

  /// Erreur de validation (données invalides)
  validation,

  /// Erreur serveur (5xx)
  server,
}

/// Résultat de la sauvegarde de l'onboarding
class OnboardingResult {
  final bool success;
  final UserProfile? profile;
  final String? errorMessage;
  final ErrorType? errorType;
  final int? interestsCreated;
  final int? preferencesCreated;

  const OnboardingResult._({
    required this.success,
    this.profile,
    this.errorMessage,
    this.errorType,
    this.interestsCreated,
    this.preferencesCreated,
  });

  /// Créer un résultat de succès
  factory OnboardingResult.success({
    required UserProfile profile,
    int? interestsCreated,
    int? preferencesCreated,
  }) {
    return OnboardingResult._(
      success: true,
      profile: profile,
      interestsCreated: interestsCreated,
      preferencesCreated: preferencesCreated,
    );
  }

  /// Créer un résultat d'erreur
  factory OnboardingResult.error(
    String message, {
    ErrorType type = ErrorType.server,
  }) {
    return OnboardingResult._(
      success: false,
      errorMessage: message,
      errorType: type,
    );
  }

  /// Message d'erreur user-friendly selon le type
  String get friendlyErrorMessage {
    if (errorMessage != null) return errorMessage!;

    switch (errorType) {
      case ErrorType.network:
        return 'Impossible de se connecter au serveur. Vérifie ta connexion internet et réessaye.';
      case ErrorType.auth:
        return 'Ta session a expiré. Veuillez te reconnecter.';
      case ErrorType.validation:
        return 'Certaines réponses sont invalides. Vérifie tes réponses.';
      case ErrorType.server:
      case null:
        return 'Une erreur est survenue côté serveur. Réessaye dans quelques instants.';
    }
  }

  @override
  String toString() {
    if (success) {
      return 'OnboardingResult.success(profile: ${profile?.id}, interests: $interestsCreated, preferences: $preferencesCreated)';
    } else {
      return 'OnboardingResult.error(type: $errorType, message: $errorMessage)';
    }
  }
}

