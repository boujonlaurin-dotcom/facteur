import 'package:freezed_annotation/freezed_annotation.dart';

import '../../feed/models/content_model.dart';

part 'digest_models.freezed.dart';
part 'digest_models.g.dart';

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
    @JsonKey(name: 'is_read') @Default(false) bool isRead,
    @JsonKey(name: 'is_saved') @Default(false) bool isSaved,
    @JsonKey(name: 'is_dismissed') @Default(false) bool isDismissed,
  }) = _DigestItem;

  factory DigestItem.fromJson(Map<String, dynamic> json) =>
      _$DigestItemFromJson(json);
}

/// Model representing the full digest response from API
@freezed
class DigestResponse with _$DigestResponse {
  const factory DigestResponse({
    @JsonKey(name: 'digest_id') required String digestId,
    @JsonKey(name: 'user_id') required String userId,
    @JsonKey(name: 'target_date') required DateTime targetDate,
    @JsonKey(name: 'generated_at') required DateTime generatedAt,
    @Default([]) List<DigestItem> items,
    @JsonKey(name: 'is_completed') @Default(false) bool isCompleted,
    @JsonKey(name: 'completed_at') DateTime? completedAt,
  }) = _DigestResponse;

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
