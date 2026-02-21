/// Constantes globales de l'application Facteur
library;

/// Configuration API
class ApiConstants {
  ApiConstants._();

  /// URL de base de l'API (à configurer via env)
  /// Sur Android Emulator, localhost = 10.0.2.2
  static String get baseUrl {
    const configured = String.fromEnvironment('API_BASE_URL');
    if (configured.isNotEmpty) {
      return configured.endsWith('/') ? configured : '$configured/';
    }

    // fallback local pour le développement
    // 1. DEV LOCAL (Décommenter une ligne selon votre device)
    // -----------------------------------------------------
    // Android Emulator :
    // return 'http://10.0.2.2:8080/api/';
    //
    // iOS Simulator / Web / Mac :
    // return 'http://localhost:8080/api/';

    // 2. PRODUCTION (Par défaut pour les Releases)
    // -----------------------------------------------------
    return 'https://facteur-production.up.railway.app/api/';
  }

  /// Timeout des requêtes HTTP
  static const Duration timeout = Duration(seconds: 30);

  /// Nombre d'items par page dans le feed
  static const int feedPageSize = 20;
}

/// Configuration Supabase
class SupabaseConstants {
  SupabaseConstants._();

  /// URL Supabase (à configurer via env)
  static final String url = _validateAndCleanSupabaseUrl(
    const String.fromEnvironment('SUPABASE_URL', defaultValue: ''),
  );

  /// Clé anonyme Supabase (à configurer via env)
  static final String anonKey = _cleanEnvVar(const String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  ));

  static String _cleanEnvVar(String value) {
    if (value.isEmpty) return value;
    // Supprimer les guillemets éventuels si passés via --dart-define="KEY=VAL"
    String cleaned = value;
    if (cleaned.startsWith('"') && cleaned.endsWith('"')) {
      cleaned = cleaned.substring(1, cleaned.length - 1);
    }
    if (cleaned.startsWith("'") && cleaned.endsWith("'")) {
      cleaned = cleaned.substring(1, cleaned.length - 1);
    }
    cleaned = cleaned.trim();
    // Supprimer le slash final pour éviter les doubles slashes dans les URLs
    while (cleaned.endsWith('/')) {
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }
    return cleaned;
  }

  /// Valide et nettoie l'URL Supabase
  /// Détecte les erreurs courantes comme l'URL du dashboard au lieu de l'URL API
  static String _validateAndCleanSupabaseUrl(String value) {
    String cleaned = _cleanEnvVar(value);

    if (cleaned.isEmpty) return cleaned;

    // Détecter si c'est l'URL du dashboard au lieu de l'URL API
    if (cleaned.contains('supabase.com/dashboard')) {
      // Essayer d'extraire le project ref
      final RegExp projectRefRegex = RegExp(r'project/([a-z0-9]+)');
      final Match? match = projectRefRegex.firstMatch(cleaned);
      if (match != null) {
        final String projectRef = match.group(1)!;
        return 'https://$projectRef.supabase.co';
      }
    }

    // Vérifier que l'URL finit par .supabase.co
    if (!cleaned.contains('.supabase.co') &&
        !cleaned.contains('localhost') &&
        !cleaned.contains('127.0.0.1')) {
      // URL invalide - retourner l'URL brute pour permettre le diagnostic
      // mais elle échouera à la connexion
      return cleaned;
    }

    return cleaned;
  }
}

/// Configuration RevenueCat
class RevenueCatConstants {
  RevenueCatConstants._();

  /// Clé API iOS
  static const String iosApiKey = String.fromEnvironment(
    'REVENUECAT_IOS_KEY',
    defaultValue: '',
  );

  /// ID du produit mensuel
  static const String monthlyProductId = 'facteur_premium_monthly';

  /// ID du produit annuel
  static const String yearlyProductId = 'facteur_premium_yearly';
}

/// Seuils de consommation
class ConsumptionThresholds {
  ConsumptionThresholds._();

  /// Seuil pour marquer un article comme consommé (secondes)
  static const int articleSeconds = 30;

  /// Seuil pour marquer une vidéo comme consommée (secondes)
  static const int videoSeconds = 60;

  /// Seuil pour marquer un podcast comme consommé (secondes)
  static const int podcastSeconds = 60;
}

/// Durée du cache
class CacheDurations {
  CacheDurations._();

  /// Durée de validité du cache du feed
  static const Duration feed = Duration(minutes: 5);

  /// Durée de validité du cache des sources
  static const Duration sources = Duration(hours: 1);

  /// Durée de validité du cache du profil
  static const Duration profile = Duration(hours: 24);
}

/// Durée de la période d'essai
class TrialConstants {
  TrialConstants._();

  /// Durée du trial en jours
  static const int durationDays = 7;

  /// Jours avant la fin du trial pour afficher l'alerte
  static const int alertDaysBefore = 2;
}

/// Objectifs de gamification
class GamificationConstants {
  GamificationConstants._();

  /// Objectifs hebdomadaires possibles
  static const List<int> weeklyGoals = [5, 10, 15];

  /// Objectif par défaut
  static const int defaultWeeklyGoal = 10;
}

/// Constantes UI
class UIConstants {
  UIConstants._();

  /// Nom de la section des contenus sauvegardés
  static const String savedSectionName = 'À consulter plus tard';

  /// Message de confirmation après sauvegarde
  static String savedConfirmMessage(String section) =>
      'Ajouté à la section "$section"';
}

/// Constantes pour le Feed
class FeedConstants {
  FeedConstants._();

  /// Mots-clés filtrés par défaut pour le mode "Rester serein"
  static const List<String> defaultFilteredKeywords = [
    'Politique',
    'Guerre',
    'Conflit',
    'Élections',
    'Inflation',
    'Grève',
    'Drame',
    'Fait divers',
    'Crise',
    'Scandale',
    'Terrorisme',
    'Corruption',
    'Procès',
    'Violence',
    'Catastrophe',
    'Manifestation',
    'Géopolitique',
    'Faits divers',
    'Trump',
    'Musk',
    'Poutine',
    'Macron',
    'Netanyahou',
    'Zelensky',
    'Ukraine',
    'Gaza',
  ];
}

/// App release tag, injected at compile time by CI.
/// Empty string in dev builds (update feature hidden).
class AppUpdateConstants {
  AppUpdateConstants._();

  /// Release tag injected by CI (e.g. "beta-20260221-1430")
  static const String releaseTag =
      String.fromEnvironment('APP_RELEASE_TAG');

  /// Whether this is a CI-built release (not a dev build)
  static bool get isReleaseBuild => releaseTag.isNotEmpty;
}

/// Liens externes
class ExternalLinks {
  ExternalLinks._();

  /// URL du formulaire de feedback (Notion)
  static const String feedbackFormUrl =
      'https://sopht.notion.site/3ba67e485f214716b9b830d145beabc3?pvs=105';
}
