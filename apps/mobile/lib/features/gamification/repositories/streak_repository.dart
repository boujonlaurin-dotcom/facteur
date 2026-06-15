import '../../../core/api/api_client.dart';
import '../models/streak_activity_model.dart';
import '../models/streak_model.dart';

class StreakRepository {
  final ApiClient _apiClient;

  StreakRepository(this._apiClient);

  Future<StreakModel> getStreak() async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        'users/streak',
      );

      if (response.statusCode == 200 && response.data != null) {
        return StreakModel.fromJson(response.data!);
      }

      // Fallback default
      return const StreakModel(
        currentStreak: 0,
        longestStreak: 0,
        weeklyCount: 0,
        weeklyGoal: 10,
        weeklyProgress: 0.0,
      );
    } catch (e) {
      // ignore: avoid_print
      print('StreakRepository: [ERROR] getStreak: $e');
      rethrow;
    }
  }

  Future<StreakActivityModel> getActivity({int days = 14}) async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        'streaks/activity',
        queryParameters: {'days': days},
      );

      if (response.statusCode == 200 && response.data != null) {
        return StreakActivityModel.fromJson(response.data!);
      }

      return const StreakActivityModel.empty();
    } catch (e) {
      // ignore: avoid_print
      print('StreakRepository: [ERROR] getActivity: $e');
      rethrow;
    }
  }
}
