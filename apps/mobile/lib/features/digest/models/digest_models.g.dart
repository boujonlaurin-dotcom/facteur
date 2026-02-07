// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'digest_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$DigestScoreBreakdownImpl _$$DigestScoreBreakdownImplFromJson(
        Map<String, dynamic> json) =>
    _$DigestScoreBreakdownImpl(
      label: json['label'] as String,
      points: (json['points'] as num).toDouble(),
      isPositive: json['is_positive'] as bool,
    );

Map<String, dynamic> _$$DigestScoreBreakdownImplToJson(
        _$DigestScoreBreakdownImpl instance) =>
    <String, dynamic>{
      'label': instance.label,
      'points': instance.points,
      'is_positive': instance.isPositive,
    };

_$DigestRecommendationReasonImpl _$$DigestRecommendationReasonImplFromJson(
        Map<String, dynamic> json) =>
    _$DigestRecommendationReasonImpl(
      label: json['label'] as String,
      scoreTotal: (json['score_total'] as num).toDouble(),
      breakdown: (json['breakdown'] as List<dynamic>)
          .map((e) => DigestScoreBreakdown.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$$DigestRecommendationReasonImplToJson(
        _$DigestRecommendationReasonImpl instance) =>
    <String, dynamic>{
      'label': instance.label,
      'score_total': instance.scoreTotal,
      'breakdown': instance.breakdown,
    };

_$SourceMiniImpl _$$SourceMiniImplFromJson(Map<String, dynamic> json) =>
    _$SourceMiniImpl(
      id: json['id'] as String?,
      name: json['name'] as String? ?? 'Inconnu',
      logoUrl: json['logo_url'] as String?,
      type: json['type'] as String?,
      theme: json['theme'] as String?,
    );

Map<String, dynamic> _$$SourceMiniImplToJson(_$SourceMiniImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'logo_url': instance.logoUrl,
      'type': instance.type,
      'theme': instance.theme,
    };

_$DigestItemImpl _$$DigestItemImplFromJson(Map<String, dynamic> json) =>
    _$DigestItemImpl(
      contentId: json['content_id'] as String,
      title: json['title'] as String? ?? 'Sans titre',
      url: json['url'] as String? ?? '',
      thumbnailUrl: json['thumbnail_url'] as String?,
      description: json['description'] as String?,
      contentType: json['content_type'] == null
          ? ContentType.article
          : _contentTypeFromJson(json['content_type'] as String?),
      durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
      publishedAt: json['published_at'] == null
          ? null
          : DateTime.parse(json['published_at'] as String),
      source: json['source'] == null
          ? null
          : SourceMini.fromJson(json['source'] as Map<String, dynamic>),
      rank: (json['rank'] as num?)?.toInt() ?? 0,
      reason: json['reason'] as String? ?? '',
      isRead: json['is_read'] as bool? ?? false,
      isSaved: json['is_saved'] as bool? ?? false,
      isDismissed: json['is_dismissed'] as bool? ?? false,
      recommendationReason: json['recommendation_reason'] == null
          ? null
          : DigestRecommendationReason.fromJson(
              json['recommendation_reason'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$$DigestItemImplToJson(_$DigestItemImpl instance) =>
    <String, dynamic>{
      'content_id': instance.contentId,
      'title': instance.title,
      'url': instance.url,
      'thumbnail_url': instance.thumbnailUrl,
      'description': instance.description,
      'content_type': _contentTypeToJson(instance.contentType),
      'duration_seconds': instance.durationSeconds,
      'published_at': instance.publishedAt?.toIso8601String(),
      'source': instance.source,
      'rank': instance.rank,
      'reason': instance.reason,
      'is_read': instance.isRead,
      'is_saved': instance.isSaved,
      'is_dismissed': instance.isDismissed,
      'recommendation_reason': instance.recommendationReason,
    };

_$DigestResponseImpl _$$DigestResponseImplFromJson(Map<String, dynamic> json) =>
    _$DigestResponseImpl(
      digestId: json['digest_id'] as String,
      userId: json['user_id'] as String,
      targetDate: DateTime.parse(json['target_date'] as String),
      generatedAt: DateTime.parse(json['generated_at'] as String),
      items: (json['items'] as List<dynamic>?)
              ?.map((e) => DigestItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      isCompleted: json['is_completed'] as bool? ?? false,
      completedAt: json['completed_at'] == null
          ? null
          : DateTime.parse(json['completed_at'] as String),
    );

Map<String, dynamic> _$$DigestResponseImplToJson(
        _$DigestResponseImpl instance) =>
    <String, dynamic>{
      'digest_id': instance.digestId,
      'user_id': instance.userId,
      'target_date': instance.targetDate.toIso8601String(),
      'generated_at': instance.generatedAt.toIso8601String(),
      'items': instance.items,
      'is_completed': instance.isCompleted,
      'completed_at': instance.completedAt?.toIso8601String(),
    };

_$DigestCompletionResponseImpl _$$DigestCompletionResponseImplFromJson(
        Map<String, dynamic> json) =>
    _$DigestCompletionResponseImpl(
      success: json['success'] as bool,
      digestId: json['digest_id'] as String,
      completedAt: json['completed_at'] == null
          ? null
          : DateTime.parse(json['completed_at'] as String),
      articlesRead: (json['articles_read'] as num?)?.toInt() ?? 0,
      articlesSaved: (json['articles_saved'] as num?)?.toInt() ?? 0,
      articlesDismissed: (json['articles_dismissed'] as num?)?.toInt() ?? 0,
      closureTimeSeconds: (json['closure_time_seconds'] as num?)?.toInt(),
      closureStreak: (json['closure_streak'] as num?)?.toInt() ?? 0,
      streakMessage: json['streak_message'] as String?,
    );

Map<String, dynamic> _$$DigestCompletionResponseImplToJson(
        _$DigestCompletionResponseImpl instance) =>
    <String, dynamic>{
      'success': instance.success,
      'digest_id': instance.digestId,
      'completed_at': instance.completedAt?.toIso8601String(),
      'articles_read': instance.articlesRead,
      'articles_saved': instance.articlesSaved,
      'articles_dismissed': instance.articlesDismissed,
      'closure_time_seconds': instance.closureTimeSeconds,
      'closure_streak': instance.closureStreak,
      'streak_message': instance.streakMessage,
    };
