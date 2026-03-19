import 'package:freezed_annotation/freezed_annotation.dart';

part 'topic_models.freezed.dart';
part 'topic_models.g.dart';

/// Source type for how the topic was added.
enum TopicSourceType {
  explicit,
  implicit,
  suggested,
}

/// User's custom topic profile from backend.
/// Created via LLM one-shot enrichment when user follows a topic.
@freezed
class UserTopicProfile with _$UserTopicProfile {
  const factory UserTopicProfile({
    required String id,
    @JsonKey(name: 'topic_name') required String name,
    @JsonKey(name: 'slug_parent') String? slugParent,
    @Default([]) List<String> keywords,
    @JsonKey(name: 'intent_description') String? intentDescription,
    @JsonKey(name: 'priority_multiplier') @Default(1.0) double priorityMultiplier,
    @JsonKey(name: 'composite_score') @Default(0.0) double compositeScore,
    @JsonKey(name: 'source_type', unknownEnumValue: TopicSourceType.explicit)
    @Default(TopicSourceType.explicit)
    TopicSourceType sourceType,
    @JsonKey(name: 'entity_type') String? entityType,
    @JsonKey(name: 'canonical_name') String? canonicalName,
    @JsonKey(name: 'created_at') DateTime? createdAt,
  }) = _UserTopicProfile;

  factory UserTopicProfile.fromJson(Map<String, dynamic> json) =>
      _$UserTopicProfileFromJson(json);
}
