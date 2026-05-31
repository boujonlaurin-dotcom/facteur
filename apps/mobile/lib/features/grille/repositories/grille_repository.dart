import 'package:dio/dio.dart';

import '../../../core/api/api_client.dart';
import '../models/grille_models.dart';

/// Aucun mot du jour disponible (404 `Aucun mot du jour disponible`).
class GrilleNotFoundException implements Exception {
  const GrilleNotFoundException();
  @override
  String toString() => 'GrilleNotFoundException';
}

/// La partie est déjà terminée — un nouvel essai est refusé (409 `deja_termine`).
class GrilleAlreadyFinishedException implements Exception {
  const GrilleAlreadyFinishedException();
  @override
  String toString() => 'GrilleAlreadyFinishedException';
}

/// Le classement n'est accessible qu'une fois la partie finie
/// (409 `partie_en_cours`).
class GrilleGameInProgressException implements Exception {
  const GrilleGameInProgressException();
  @override
  String toString() => 'GrilleGameInProgressException';
}

/// Accès réseau à « La Grille du jour ».
///
/// Base URL du client finit déjà par `/api/` → chemins relatifs `grille/...`.
/// Un essai refusé (`valide == false`) est une **donnée** ([GrilleGuessResponse]),
/// pas une exception : seuls les vrais codes d'erreur HTTP lèvent.
class GrilleRepository {
  GrilleRepository(this._apiClient);

  final ApiClient _apiClient;

  /// `GET grille/today`.
  Future<GrilleTodayResponse> getToday() async {
    try {
      final response = await _apiClient.dio.get<dynamic>('grille/today');
      return GrilleTodayResponse.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw const GrilleNotFoundException();
      }
      rethrow;
    }
  }

  /// `POST grille/today/guess` — un refus (`valide == false`) revient en data.
  Future<GrilleGuessResponse> submitGuess(String mot) async {
    try {
      final response = await _apiClient.dio.post<dynamic>(
        'grille/today/guess',
        data: {'mot': mot},
      );
      return GrilleGuessResponse.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 409) {
        throw const GrilleAlreadyFinishedException();
      }
      if (code == 404) {
        throw const GrilleNotFoundException();
      }
      rethrow;
    }
  }

  /// `GET grille/today/leaderboard` (partie terminée requise).
  Future<GrilleLeaderboardResponse> getLeaderboard() async {
    try {
      final response =
          await _apiClient.dio.get<dynamic>('grille/today/leaderboard');
      return GrilleLeaderboardResponse.fromJson(
        response.data as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 409) {
        throw const GrilleGameInProgressException();
      }
      if (code == 404) {
        throw const GrilleNotFoundException();
      }
      rethrow;
    }
  }
}
