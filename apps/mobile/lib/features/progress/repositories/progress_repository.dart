import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/api/api_client.dart';
import '../models/progress_models.dart';

// Provider definitions
final progressRepositoryProvider = Provider<ProgressRepository>((ref) {
  final supabase = Supabase.instance.client;
  final apiClient = ApiClient(supabase);
  return ProgressRepository(apiClient);
});

final myProgressProvider = FutureProvider<List<UserTopicProgress>>((ref) async {
  final repository = ref.watch(progressRepositoryProvider);
  return repository.getMyProgress();
});

class ProgressRepository {
  final ApiClient _apiClient;

  ProgressRepository(this._apiClient);

  /// Fetches users progress list
  Future<List<UserTopicProgress>> getMyProgress() async {
    final response = await _apiClient.get(
      'progress/',
    );

    return (response as List)
        .map((e) => UserTopicProgress.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Follow a new topic
  Future<UserTopicProgress> followTopic(String topic) async {
    final response = await _apiClient.post(
      'progress/follow',
      body: {'topic': topic},
    );

    return UserTopicProgress.fromJson(response as Map<String, dynamic>);
  }

  /// Get a quiz for a topic
  Future<TopicQuiz> getQuiz(String topic) async {
    final response = await _apiClient.get(
      'progress/quiz',
      queryParameters: {'topic': topic},
    );

    return TopicQuiz.fromJson(response as Map<String, dynamic>);
  }

  /// Submit quiz answer
  Future<QuizResultResponse> submitQuiz(
      String quizId, int selectedOptionIndex) async {
    final response = await _apiClient.post(
      'progress/quiz/submit',
      body: {
        'quiz_id': quizId,
        'selected_option_index': selectedOptionIndex,
      },
    );

    return QuizResultResponse.fromJson(response as Map<String, dynamic>);
  }
}
