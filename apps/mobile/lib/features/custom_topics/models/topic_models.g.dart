// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'topic_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$UserTopicProfileImpl _$$UserTopicProfileImplFromJson(
        Map<String, dynamic> json) =>
    _$UserTopicProfileImpl(
      id: json['id'] as String,
      name: json['topic_name'] as String,
      slugParent: json['slug_parent'] as String?,
      keywords: (json['keywords'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      intentDescription: json['intent_description'] as String?,
      priorityMultiplier:
          (json['priority_multiplier'] as num?)?.toDouble() ?? 1.0,
      compositeScore: (json['composite_score'] as num?)?.toDouble() ?? 0.0,
      sourceType: $enumDecodeNullable(
              _$TopicSourceTypeEnumMap, json['source_type'],
              unknownValue: TopicSourceType.explicit) ??
          TopicSourceType.explicit,
      entityType: json['entity_type'] as String?,
      canonicalName: json['canonical_name'] as String?,
      createdAt: json['created_at'] == null
          ? null
          : DateTime.parse(json['created_at'] as String),
    );

Map<String, dynamic> _$$UserTopicProfileImplToJson(
        _$UserTopicProfileImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'topic_name': instance.name,
      'slug_parent': instance.slugParent,
      'keywords': instance.keywords,
      'intent_description': instance.intentDescription,
      'priority_multiplier': instance.priorityMultiplier,
      'composite_score': instance.compositeScore,
      'source_type': _$TopicSourceTypeEnumMap[instance.sourceType]!,
      'entity_type': instance.entityType,
      'canonical_name': instance.canonicalName,
      'created_at': instance.createdAt?.toIso8601String(),
    };

const _$TopicSourceTypeEnumMap = {
  TopicSourceType.explicit: 'explicit',
  TopicSourceType.implicit: 'implicit',
  TopicSourceType.suggested: 'suggested',
};
