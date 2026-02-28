import 'package:freezed_annotation/freezed_annotation.dart';

import '../../feed/models/content_model.dart';

part 'digest_models.freezed.dart';
part 'digest_models.g.dart';

/// Individual scoring contribution for a digest item
@freezed
class DigestScoreBreakdown with _$DigestScoreBreakdown {
  const factory DigestScoreBreakdown({
    required String label,
    required double points,
    @JsonKey(name: 'is_positive') required bool isPositive,
  }) = _DigestScoreBreakdown;

  factory DigestScoreBreakdown.fromJson(Map<String, dynamic> json) =>
      _$DigestScoreBreakdownFromJson(json);
}

/// Complete recommendation reasoning with score breakdown
@freezed
class DigestRecommendationReason with _$DigestRecommendationReason {
  const factory DigestRecommendationReason({
    required String label,
    @JsonKey(name: 'score_total') required double scoreTotal,
    required List<DigestScoreBreakdown> breakdown,
  }) = _DigestRecommendationReason;

  factory DigestRecommendationReason.fromJson(Map<String, dynamic> json) =>
      _$DigestRecommendationReasonFromJson(json);
}

/// Model representing a source in minimal form (for digest items)
@freezed
class SourceMini with _$SourceMini {
  const factory SourceMini({
    @JsonKey(name: 'id') String? id,
    @Default('Inconnu') String name,
    @JsonKey(name: 'logo_url') String? logoUrl,
    @JsonKey(name: 'type') String? type,
    String? theme,
  }) = _SourceMini;

  factory SourceMini.fromJson(Map<String, dynamic> json) =>
      _$SourceMiniFromJson(json);
}

/// Model representing a single item in the daily digest
@freezed
class DigestItem with _$DigestItem {
  const factory DigestItem({
    @JsonKey(name: 'content_id') required String contentId,
    @Default('Sans titre') String title,
    @Default('') String url,
    @JsonKey(name: 'thumbnail_url') String? thumbnailUrl,
    String? description,
    @JsonKey(name: 'html_content') String? htmlContent,
    @Default([]) List<String> topics,
    @JsonKey(
        name: 'content_type',
        fromJson: _contentTypeFromJson,
        toJson: _contentTypeToJson)
    @Default(ContentType.article)
    ContentType contentType,
    @JsonKey(name: 'duration_seconds') int? durationSeconds,
    @JsonKey(name: 'published_at') DateTime? publishedAt,
    SourceMini? source,
    @Default(0) int rank,
    @Default('') String reason,
    @JsonKey(name: 'is_followed_source') @Default(false) bool isFollowedSource,
    @JsonKey(name: 'is_paid') @Default(false) bool isPaid,
    @JsonKey(name: 'is_read') @Default(false) bool isRead,
    @JsonKey(name: 'is_saved') @Default(false) bool isSaved,
    @JsonKey(name: 'is_liked') @Default(false) bool isLiked,
    @JsonKey(name: 'is_dismissed') @Default(false) bool isDismissed,
    @JsonKey(name: 'recommendation_reason')
    DigestRecommendationReason? recommendationReason,
    @JsonKey(name: 'note_text') String? noteText,
  }) = _DigestItem;

  factory DigestItem.fromJson(Map<String, dynamic> json) =>
      _$DigestItemFromJson(json);
}

/// Model representing a topic cluster in the digest (topics_v1 format)
@freezed
class DigestTopic with _$DigestTopic {
  const DigestTopic._();

  const factory DigestTopic({
    @JsonKey(name: 'topic_id') required String topicId,
    required String label,
    @Default(1) int rank,
    @Default('') String reason,
    @JsonKey(name: 'is_trending') @Default(false) bool isTrending,
    @JsonKey(name: 'is_une') @Default(false) bool isUne,
    String? theme,
    @JsonKey(name: 'topic_score') @Default(0.0) double topicScore,
    @Default([]) List<String> subjects,
    @Default([]) List<DigestItem> articles,
  }) = _DigestTopic;

  /// A topic is "covered" when at least one article has been interacted with
  bool get isCovered =>
      articles.any((a) => a.isRead || a.isSaved || a.isDismissed);

  /// Number of sources covering this topic
  int get sourceCount => articles.length;

  factory DigestTopic.fromJson(Map<String, dynamic> json) =>
      _$DigestTopicFromJson(json);
}

/// Model representing the full digest response from API
@freezed
class DigestResponse with _$DigestResponse {
  const DigestResponse._();

  const factory DigestResponse({
    @JsonKey(name: 'digest_id') required String digestId,
    @JsonKey(name: 'user_id') required String userId,
    @JsonKey(name: 'target_date') required DateTime targetDate,
    @JsonKey(name: 'generated_at') required DateTime generatedAt,
    @JsonKey(defaultValue: 'pour_vous') @Default('pour_vous') String mode,
    @JsonKey(name: 'format_version') @Default('topics_v1') String formatVersion,
    @Default([]) List<DigestItem> items,
    @Default([]) List<DigestTopic> topics,
    @JsonKey(name: 'completion_threshold') @Default(5) int completionThreshold,
    @JsonKey(name: 'is_completed') @Default(false) bool isCompleted,
    @JsonKey(name: 'completed_at') DateTime? completedAt,
  }) = _DigestResponse;

  /// Whether this digest uses the topics layout
  bool get usesTopics => formatVersion == 'topics_v1' && topics.isNotEmpty;

  /// Number of covered topics (for progress tracking)
  int get coveredTopicCount => topics.where((t) => t.isCovered).length;

  factory DigestResponse.fromJson(Map<String, dynamic> json) =>
      _$DigestResponseFromJson(json);
}

/// Model representing the digest completion response from API
/// Returned when completing a digest via POST /api/digest/{id}/complete
@freezed
class DigestCompletionResponse with _$DigestCompletionResponse {
  const factory DigestCompletionResponse({
    required bool success,
    @JsonKey(name: 'digest_id') required String digestId,
    @JsonKey(name: 'completed_at') DateTime? completedAt,
    @JsonKey(name: 'articles_read') @Default(0) int articlesRead,
    @JsonKey(name: 'articles_saved') @Default(0) int articlesSaved,
    @JsonKey(name: 'articles_dismissed') @Default(0) int articlesDismissed,
    @JsonKey(name: 'closure_time_seconds') int? closureTimeSeconds,
    @JsonKey(name: 'closure_streak') @Default(0) int closureStreak,
    @JsonKey(name: 'streak_message') String? streakMessage,
  }) = _DigestCompletionResponse;

  factory DigestCompletionResponse.fromJson(Map<String, dynamic> json) =>
      _$DigestCompletionResponseFromJson(json);
}

// Helper functions for ContentType serialization
ContentType _contentTypeFromJson(String? value) {
  return ContentType.values.firstWhere(
    (e) => e.name == value?.toLowerCase(),
    orElse: () => ContentType.article,
  );
}

String _contentTypeToJson(ContentType type) => type.name;
