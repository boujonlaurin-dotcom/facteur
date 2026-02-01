// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'digest_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$SourceMiniImpl _$$SourceMiniImplFromJson(Map<String, dynamic> json) =>
    _$SourceMiniImpl(
      name: json['name'] as String,
      logoUrl: json['logoUrl'] as String?,
      theme: json['theme'] as String?,
    );

Map<String, dynamic> _$$SourceMiniImplToJson(_$SourceMiniImpl instance) =>
    <String, dynamic>{
      'name': instance.name,
      'logoUrl': instance.logoUrl,
      'theme': instance.theme,
    };

_$DigestItemImpl _$$DigestItemImplFromJson(Map<String, dynamic> json) =>
    _$DigestItemImpl(
      contentId: json['contentId'] as String,
      title: json['title'] as String,
      url: json['url'] as String,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      description: json['description'] as String?,
      contentType: _contentTypeFromJson(json['contentType'] as String?),
      durationSeconds: (json['durationSeconds'] as num?)?.toInt(),
      publishedAt: DateTime.parse(json['publishedAt'] as String),
      source: SourceMini.fromJson(json['source'] as Map<String, dynamic>),
      rank: (json['rank'] as num).toInt(),
      reason: json['reason'] as String,
      isRead: json['isRead'] as bool? ?? false,
      isSaved: json['isSaved'] as bool? ?? false,
      isDismissed: json['isDismissed'] as bool? ?? false,
    );

Map<String, dynamic> _$$DigestItemImplToJson(_$DigestItemImpl instance) =>
    <String, dynamic>{
      'contentId': instance.contentId,
      'title': instance.title,
      'url': instance.url,
      'thumbnailUrl': instance.thumbnailUrl,
      'description': instance.description,
      'contentType': _contentTypeToJson(instance.contentType),
      'durationSeconds': instance.durationSeconds,
      'publishedAt': instance.publishedAt.toIso8601String(),
      'source': instance.source,
      'rank': instance.rank,
      'reason': instance.reason,
      'isRead': instance.isRead,
      'isSaved': instance.isSaved,
      'isDismissed': instance.isDismissed,
    };

_$DigestResponseImpl _$$DigestResponseImplFromJson(Map<String, dynamic> json) =>
    _$DigestResponseImpl(
      digestId: json['digestId'] as String,
      userId: json['userId'] as String,
      targetDate: DateTime.parse(json['targetDate'] as String),
      generatedAt: DateTime.parse(json['generatedAt'] as String),
      items: (json['items'] as List<dynamic>)
          .map((e) => DigestItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      isCompleted: json['isCompleted'] as bool? ?? false,
      completedAt: json['completedAt'] == null
          ? null
          : DateTime.parse(json['completedAt'] as String),
    );

Map<String, dynamic> _$$DigestResponseImplToJson(
        _$DigestResponseImpl instance) =>
    <String, dynamic>{
      'digestId': instance.digestId,
      'userId': instance.userId,
      'targetDate': instance.targetDate.toIso8601String(),
      'generatedAt': instance.generatedAt.toIso8601String(),
      'items': instance.items,
      'isCompleted': instance.isCompleted,
      'completedAt': instance.completedAt?.toIso8601String(),
    };
