import 'package:freezed_annotation/freezed_annotation.dart';

part 'progress_models.freezed.dart';
part 'progress_models.g.dart';

@freezed
class UserTopicProgress with _$UserTopicProgress {
  const factory UserTopicProgress({
    required String id,
    @JsonKey(name: 'user_id') required String userId,
    required String topic,
    required int level,
    required int points,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
  }) = _UserTopicProgress;

  factory UserTopicProgress.fromJson(Map<String, dynamic> json) =>
      _$UserTopicProgressFromJson(json);
}

@freezed
class TopicQuiz with _$TopicQuiz {
  const factory TopicQuiz({
    required String id,
    required String topic,
    required String question,
    required List<String> options,
    required int difficulty,
  }) = _TopicQuiz;

  factory TopicQuiz.fromJson(Map<String, dynamic> json) =>
      _$TopicQuizFromJson(json);
}

@freezed
class QuizResultResponse with _$QuizResultResponse {
  const factory QuizResultResponse({
    @JsonKey(name: 'is_correct') required bool isCorrect,
    @JsonKey(name: 'correct_answer') required int correctAnswer,
    @JsonKey(name: 'points_earned') required int pointsEarned,
    @JsonKey(name: 'new_level') int? newLevel,
    required String message,
  }) = _QuizResultResponse;

  factory QuizResultResponse.fromJson(Map<String, dynamic> json) =>
      _$QuizResultResponseFromJson(json);
}
