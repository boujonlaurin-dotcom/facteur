import '../../../core/api/api_client.dart';
import '../models/feedback_models.dart';

/// Repository pour le système de feedback utilisateur (Epic 13).
///
/// Toutes les méthodes "best-effort" échouent silencieusement : le feedback
/// ne doit jamais casser le flux du moment de fermeture.
class FeedbackRepository {
  final ApiClient _apiClient;

  FeedbackRepository(this._apiClient);

  /// Enregistre le micro-feedback emoji du jour ("low" | "ok" | "high").
  Future<void> submitSentiment(String sentiment, {DateTime? date}) async {
    try {
      await _apiClient.dio.post<dynamic>(
        'feedback/sentiment',
        data: {
          'sentiment': sentiment,
          if (date != null)
            'digest_date': date.toIso8601String().split('T').first,
        },
      );
    } catch (e) {
      // ignore: avoid_print
      print('FeedbackRepository: submitSentiment failed: $e');
    }
  }

  /// Récupère le statut de l'invitation au call.
  /// Renvoie `hidden()` en cas d'erreur (on ne dérange jamais par défaut).
  Future<FeedbackInviteStatus> getInviteStatus() async {
    try {
      final response = await _apiClient.dio.get<dynamic>('feedback/invite');
      if (response.statusCode == 200 && response.data != null) {
        return FeedbackInviteStatus.fromJson(
          response.data as Map<String, dynamic>,
        );
      }
    } catch (e) {
      // ignore: avoid_print
      print('FeedbackRepository: getInviteStatus failed: $e');
    }
    return FeedbackInviteStatus.hidden();
  }

  /// Marque la modal comme affichée (incrémente le compteur côté backend).
  Future<void> markInviteShown() async {
    try {
      await _apiClient.dio.post<dynamic>('feedback/invite/shown');
    } catch (e) {
      // ignore: avoid_print
      print('FeedbackRepository: markInviteShown failed: $e');
    }
  }

  /// Enregistre l'action de l'utilisateur ("accepted" | "declined").
  Future<void> submitInviteAction(String action) async {
    try {
      await _apiClient.dio.post<dynamic>(
        'feedback/invite/action',
        data: {'action': action},
      );
    } catch (e) {
      // ignore: avoid_print
      print('FeedbackRepository: submitInviteAction failed: $e');
    }
  }
}
