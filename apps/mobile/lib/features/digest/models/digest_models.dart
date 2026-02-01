import 'package:freezed_annotation/freezed_annotation.dart';

import '../../feed/models/content_model.dart';

part 'digest_models.freezed.dart';
part 'digest_models.g.dart';

/// Model representing a source in minimal form (for digest items)
@freezed
class SourceMini with _$SourceMini {
  const factory SourceMini({
    required String name,
    String? logoUrl,
    String? theme,
  }) = _SourceMini;

  factory SourceMini.fromJson(Map<String, dynamic> json) =>
      _$SourceMiniFromJson(json);
}

/// Model representing a single item in the daily digest
@freezed
class DigestItem with _$DigestItem {
  const factory DigestItem({
    required String contentId,
    required String title,
    required String url,
    String? thumbnailUrl,
    String? description,
    @JsonKey(fromJson: _contentTypeFromJson, toJson: _contentTypeToJson)
    required ContentType contentType,
    int? durationSeconds,
    required DateTime publishedAt,
    required SourceMini source,
    required int rank,
    required String reason,
    @Default(false) bool isRead,
    @Default(false) bool isSaved,
    @Default(false) bool isDismissed,
  }) = _DigestItem;

  factory DigestItem.fromJson(Map<String, dynamic> json) =>
      _$DigestItemFromJson(json);
}

/// Model representing the full digest response from API
@freezed
class DigestResponse with _$DigestResponse {
  const factory DigestResponse({
    required String digestId,
    required String userId,
    required DateTime targetDate,
    required DateTime generatedAt,
    required List<DigestItem> items,
    @Default(false) bool isCompleted,
    DateTime? completedAt,
  }) = _DigestResponse;

  factory DigestResponse.fromJson(Map<String, dynamic> json) =>
      _$DigestResponseFromJson(json);
}

// Helper functions for ContentType serialization
ContentType _contentTypeFromJson(String? value) {
  return ContentType.values.firstWhere(
    (e) => e.name == value?.toLowerCase(),
    orElse: () => ContentType.article,
  );
}

String _contentTypeToJson(ContentType type) => type.name;
