/// Traduction des messages d'erreur Supabase Auth en français
library;

/// Utilitaire pour traduire les erreurs d'authentification en messages français
class AuthErrorMessages {
  AuthErrorMessages._();

  /// Traduit un message d'erreur Supabase en français
  static String translate(String? message) {
    if (message == null || message.isEmpty) {
      return 'Une erreur inattendue s\'est produite.';
    }

    final lowerMessage = message.toLowerCase();

    // ============================================
    // Erreurs de connexion
    // ============================================

    if (lowerMessage.contains('invalid login credentials')) {
      return 'Email ou mot de passe incorrect.';
    }

    if (lowerMessage.contains('email not confirmed')) {
      return 'Ton email n\'est pas encore confirmé. Vérifie ta boîte de réception.';
    }

    if (lowerMessage.contains('invalid email')) {
      return 'L\'adresse email semble incorrecte.';
    }

    // ============================================
    // Erreurs d'inscription
    // ============================================

    if (lowerMessage.contains('user already registered')) {
      return 'Cette adresse email est déjà utilisée.';
    }

    if (lowerMessage.contains('password should be at least')) {
      return 'Le mot de passe doit contenir au moins 6 caractères.';
    }

    if (lowerMessage.contains('signup is disabled')) {
      return 'Les inscriptions sont temporairement désactivées.';
    }

    if (lowerMessage.contains('unable to validate email address')) {
      return 'Cette adresse email ne semble pas valide.';
    }

    // ============================================
    // Rate limiting
    // ============================================

    if (lowerMessage.contains('too many requests') ||
        lowerMessage.contains('rate limit') ||
        lowerMessage.contains('email rate limit exceeded')) {
      return 'Trop de tentatives. Réessaie dans quelques minutes.';
    }

    if (lowerMessage.contains('for security purposes')) {
      return 'Pour des raisons de sécurité, attends quelques secondes avant de réessayer.';
    }

    // ============================================
    // Erreurs réseau
    // ============================================

    if (lowerMessage.contains('network') ||
        lowerMessage.contains('connection') ||
        lowerMessage.contains('socket')) {
      return 'Problème de connexion. Vérifie ton réseau internet.';
    }

    // ============================================
    // Réinitialisation mot de passe
    // ============================================

    if (lowerMessage.contains('user not found')) {
      return 'Aucun compte trouvé avec cette adresse email.';
    }

    // ============================================
    // OAuth / Social login
    // ============================================

    if (lowerMessage.contains('oauth') || lowerMessage.contains('provider')) {
      return 'Erreur lors de la connexion avec ce service.';
    }

    if (lowerMessage.contains('popup closed') ||
        lowerMessage.contains('cancelled')) {
      return 'Connexion annulée.';
    }

    // ============================================
    // Erreurs de lien / Validation
    // ============================================

    if (lowerMessage.contains('email link is invalid or has expired')) {
      return 'Le lien de confirmation est invalide ou a expiré.';
    }

    if (lowerMessage.contains('confirmation_token_valid')) {
      return 'Le code de confirmation est invalide.';
    }

    // ============================================
    // Erreurs de configuration / Réseau critiques
    // ============================================

    if (lowerMessage.contains('bad request') ||
        lowerMessage.contains('invalid request')) {
      return 'Erreur de configuration. Veuillez réessayer plus tard.';
    }

    if (lowerMessage.contains('unauthorized') || lowerMessage.contains('401')) {
      return 'Accès non autorisé. Veuillez vérifier vos identifiants.';
    }

    if (lowerMessage.contains('forbidden') || lowerMessage.contains('403')) {
      return 'Accès refusé. Votre compte n\'a pas les permissions nécessaires.';
    }

    // ============================================
    // Session / Token - Plus spécifique
    // ============================================

    if (lowerMessage.contains('session not found') ||
        lowerMessage.contains('token has expired') ||
        lowerMessage.contains('jwt expired')) {
      return 'Ta session a expiré. Reconnecte-toi.';
    }

    if (lowerMessage.contains('invalid token') ||
        lowerMessage.contains('invalid signature')) {
      return 'Session invalide. Reconnecte-toi.';
    }

    // ============================================
    // Par défaut
    // ============================================

    return 'Une erreur est survenue. Réessaie plus tard.';
  }
}
