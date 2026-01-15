/// Constantes globales de l'application Facteur
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

/// Configuration API
class ApiConstants {
  ApiConstants._();

  /// URL de base de l'API (à configurer via env)
  /// Sur Android Emulator, localhost = 10.0.2.2
  static String get baseUrl {
    const configured = String.fromEnvironment('API_BASE_URL');
    if (configured.isNotEmpty) {
      // S'assurer que l'URL se termine par un slash pour Dio
      return configured.endsWith('/') ? configured : '$configured/';
    }

    if (!kIsWeb && Platform.isAndroid) {
      return 'http://10.0.2.2:8000/api/';
    }

    return 'http://localhost:8000/api/';
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
  static final String url = _cleanEnvVar(const String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  ));

  /// Clé anonyme Supabase (à configurer via env)
  static final String anonKey = _cleanEnvVar(const String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  ));

  static String _cleanEnvVar(String value) {
    if (value.isEmpty) return value;
    // Supprimer les guillemets éventuels si passés via --dart-define="KEY=VAL"
    if (value.startsWith('"') && value.endsWith('"')) {
      return value.substring(1, value.length - 1);
    }
    if (value.startsWith("'") && value.endsWith("'")) {
      return value.substring(1, value.length - 1);
    }
    return value.trim();
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
