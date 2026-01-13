import 'package:dio/dio.dart';

import '../../features/onboarding/providers/onboarding_provider.dart';
import '../../models/onboarding_result.dart';
import '../../models/user_profile.dart';
import 'api_client.dart';

/// Service API pour les opérations liées aux utilisateurs
class UserApiService {
  final ApiClient _apiClient;

  UserApiService(this._apiClient);

  /// Sauvegarde les réponses de l'onboarding
  ///
  /// Envoie toutes les réponses de l'onboarding à l'API backend qui :
  /// - Crée/met à jour le profil utilisateur
  /// - Stocke les préférences dans user_preferences
  /// - Stocke les intérêts dans user_interests avec pondération
  /// - Marque onboarding_completed = true
  ///
  /// Retourne [OnboardingResult] avec le profil créé ou une erreur
  Future<OnboardingResult> saveOnboarding(OnboardingAnswers answers) async {
    try {
      final response = await _apiClient.dio.post(
        '/users/onboarding',
        data: {'answers': _formatAnswersForApi(answers)},
      );

      // Parser la réponse de succès
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw Exception('Invalid response format');
      }
      final profileData = data['profile'];
      if (profileData is! Map<String, dynamic>) {
        throw Exception('Invalid profile format');
      }
      final profile = UserProfile.fromJson(profileData);

      return OnboardingResult.success(
        profile: profile,
        interestsCreated: data['interests_created'] as int?,
        preferencesCreated: data['preferences_created'] as int?,
      );
    } on DioException catch (e) {
      return _handleDioError(e);
    } catch (e) {
      // Erreur inattendue
      return OnboardingResult.error(
        'Une erreur inattendue est survenue : ${e.toString()}',
        type: ErrorType.server,
      );
    }
  }

  /// Récupère le profil utilisateur
  Future<UserProfile?> getProfile() async {
    try {
      final response = await _apiClient.dio.get('/users/profile');
      final data = response.data as Map<String, dynamic>;
      return UserProfile.fromJson(data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null; // Profil pas encore créé
      }
      rethrow;
    }
  }

  /// Met à jour le profil utilisateur
  Future<UserProfile> updateProfile(Map<String, dynamic> updates) async {
    final response = await _apiClient.dio.put('/users/profile', data: updates);
    final data = response.data as Map<String, dynamic>;
    return UserProfile.fromJson(data);
  }

  /// Formate les réponses pour l'API (camelCase → snake_case)
  Map<String, dynamic> _formatAnswersForApi(OnboardingAnswers answers) {
    return {
      'objective': answers.objective,
      'age_range': answers.ageRange,
      'gender': answers.gender,
      'approach': answers.approach,
      'perspective': answers.perspective,
      'response_style': answers.responseStyle,
      'content_recency': answers.contentRecency,
      'gamification_enabled': answers.gamificationEnabled,
      'weekly_goal': answers.weeklyGoal,
      'themes': answers.themes,
      'preferred_sources': answers.preferredSources,
      'format_preference': answers.formatPreference,
      'personal_goal': answers.personalGoal,
    };
  }

  /// Gère les erreurs Dio et retourne un OnboardingResult approprié
  OnboardingResult _handleDioError(DioException e) {
    final statusCode = e.response?.statusCode;

    // Erreur de validation (422)
    if (statusCode == 422) {
      final errorData = e.response?.data;
      String message = 'Données invalides. Veuillez vérifier vos réponses.';

      // Extraire les détails de validation si disponibles
      if (errorData is Map && errorData['error'] != null) {
        final error = errorData['error'] as Map;
        if (error['message'] != null) {
          message = error['message'] as String;
        }
      }

      return OnboardingResult.error(message, type: ErrorType.validation);
    }

    // Erreur d'authentification (401)
    if (statusCode == 401) {
      return OnboardingResult.error(
        'Ta session a expiré. Veuillez te reconnecter.',
        type: ErrorType.auth,
      );
    }

    // Erreur de permissions (403)
    if (statusCode == 403) {
      return OnboardingResult.error(
        'Accès non autorisé.',
        type: ErrorType.auth,
      );
    }

    // Erreurs serveur (5xx)
    if (statusCode != null && statusCode >= 500) {
      return OnboardingResult.error(
        'Le serveur rencontre des difficultés. Réessaye dans quelques instants.',
        type: ErrorType.server,
      );
    }

    // Erreurs réseau (timeout, connexion)
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.connectionError) {
      return OnboardingResult.error(
        'Impossible de se connecter au serveur. Vérifie ta connexion internet.',
        type: ErrorType.network,
      );
    }

    // Erreur générique
    return OnboardingResult.error(
      'Une erreur est survenue : ${e.message}',
      type: ErrorType.server,
    );
  }
}
