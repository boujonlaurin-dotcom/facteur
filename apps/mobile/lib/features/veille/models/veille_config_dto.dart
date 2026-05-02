import 'package:flutter/foundation.dart';

/// DTOs miroir de `packages/api/app/schemas/veille.py` (réponses + bodies).

@immutable
class VeilleTopicDto {
  final String id;
  final String topicId;
  final String label;
  final String kind;
  final String? reason;
  final int position;

  const VeilleTopicDto({
    required this.id,
    required this.topicId,
    required this.label,
    required this.kind,
    required this.reason,
    required this.position,
  });

  factory VeilleTopicDto.fromJson(Map<String, dynamic> json) {
    return VeilleTopicDto(
      id: json['id'] as String,
      topicId: json['topic_id'] as String,
      label: json['label'] as String,
      kind: json['kind'] as String,
      reason: json['reason'] as String?,
      position: (json['position'] as num?)?.toInt() ?? 0,
    );
  }
}

@immutable
class VeilleSourceLiteDto {
  final String id;
  final String name;
  final String url;
  final String feedUrl;
  final String theme;
  final String type;
  final bool isCurated;
  final String? logoUrl;

  const VeilleSourceLiteDto({
    required this.id,
    required this.name,
    required this.url,
    required this.feedUrl,
    required this.theme,
    required this.type,
    required this.isCurated,
    required this.logoUrl,
  });

  factory VeilleSourceLiteDto.fromJson(Map<String, dynamic> json) {
    return VeilleSourceLiteDto(
      id: json['id'] as String,
      name: json['name'] as String,
      url: json['url'] as String,
      feedUrl: json['feed_url'] as String,
      theme: json['theme'] as String,
      type: json['type'] as String,
      isCurated: json['is_curated'] as bool? ?? false,
      logoUrl: json['logo_url'] as String?,
    );
  }
}

@immutable
class VeilleSourceDto {
  final String id;
  final VeilleSourceLiteDto source;
  final String kind;
  final String? why;
  final int position;

  const VeilleSourceDto({
    required this.id,
    required this.source,
    required this.kind,
    required this.why,
    required this.position,
  });

  factory VeilleSourceDto.fromJson(Map<String, dynamic> json) {
    return VeilleSourceDto(
      id: json['id'] as String,
      source:
          VeilleSourceLiteDto.fromJson(json['source'] as Map<String, dynamic>),
      kind: json['kind'] as String,
      why: json['why'] as String?,
      position: (json['position'] as num?)?.toInt() ?? 0,
    );
  }
}

@immutable
class VeilleConfigDto {
  final String id;
  final String userId;
  final String themeId;
  final String themeLabel;
  final String frequency;
  final int? dayOfWeek;
  final int deliveryHour;
  final String timezone;
  final String status;
  final DateTime? lastDeliveredAt;
  final DateTime? nextScheduledAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<VeilleTopicDto> topics;
  final List<VeilleSourceDto> sources;

  const VeilleConfigDto({
    required this.id,
    required this.userId,
    required this.themeId,
    required this.themeLabel,
    required this.frequency,
    required this.dayOfWeek,
    required this.deliveryHour,
    required this.timezone,
    required this.status,
    required this.lastDeliveredAt,
    required this.nextScheduledAt,
    required this.createdAt,
    required this.updatedAt,
    required this.topics,
    required this.sources,
  });

  factory VeilleConfigDto.fromJson(Map<String, dynamic> json) {
    return VeilleConfigDto(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      themeId: json['theme_id'] as String,
      themeLabel: json['theme_label'] as String,
      frequency: json['frequency'] as String,
      dayOfWeek: (json['day_of_week'] as num?)?.toInt(),
      deliveryHour: (json['delivery_hour'] as num?)?.toInt() ?? 7,
      timezone: (json['timezone'] as String?) ?? 'Europe/Paris',
      status: json['status'] as String,
      lastDeliveredAt: json['last_delivered_at'] != null
          ? DateTime.parse(json['last_delivered_at'] as String)
          : null,
      nextScheduledAt: json['next_scheduled_at'] != null
          ? DateTime.parse(json['next_scheduled_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      topics: ((json['topics'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(VeilleTopicDto.fromJson)
          .toList(),
      sources: ((json['sources'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(VeilleSourceDto.fromJson)
          .toList(),
    );
  }
}

// ─── Bodies (POST/PATCH) ──────────────────────────────────────────────────

@immutable
class VeilleTopicSelectionRequest {
  final String topicId;
  final String label;
  final String kind;
  final String? reason;
  final int position;

  const VeilleTopicSelectionRequest({
    required this.topicId,
    required this.label,
    required this.kind,
    this.reason,
    this.position = 0,
  });

  Map<String, dynamic> toJson() => {
        'topic_id': topicId,
        'label': label,
        'kind': kind,
        if (reason != null) 'reason': reason,
        'position': position,
      };
}

@immutable
class VeilleNicheCandidateRequest {
  final String name;
  final String url;
  final String? why;

  const VeilleNicheCandidateRequest({
    required this.name,
    required this.url,
    this.why,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'url': url,
        if (why != null) 'why': why,
      };
}

@immutable
class VeilleSourceSelectionRequest {
  final String kind;
  final String? sourceId;
  final VeilleNicheCandidateRequest? nicheCandidate;
  final String? why;
  final int position;

  const VeilleSourceSelectionRequest({
    required this.kind,
    this.sourceId,
    this.nicheCandidate,
    this.why,
    this.position = 0,
  });

  Map<String, dynamic> toJson() => {
        'kind': kind,
        if (sourceId != null) 'source_id': sourceId,
        if (nicheCandidate != null) 'niche_candidate': nicheCandidate!.toJson(),
        if (why != null) 'why': why,
        'position': position,
      };
}

@immutable
class VeilleConfigUpsertRequest {
  final String themeId;
  final String themeLabel;
  final List<VeilleTopicSelectionRequest> topics;
  final List<VeilleSourceSelectionRequest> sourceSelections;
  final String frequency;
  final int? dayOfWeek;
  final int deliveryHour;
  final String timezone;

  const VeilleConfigUpsertRequest({
    required this.themeId,
    required this.themeLabel,
    required this.topics,
    required this.sourceSelections,
    required this.frequency,
    required this.dayOfWeek,
    this.deliveryHour = 7,
    this.timezone = 'Europe/Paris',
  });

  Map<String, dynamic> toJson() => {
        'theme_id': themeId,
        'theme_label': themeLabel,
        'topics': topics.map((t) => t.toJson()).toList(),
        'source_selections': sourceSelections.map((s) => s.toJson()).toList(),
        'frequency': frequency,
        if (dayOfWeek != null) 'day_of_week': dayOfWeek,
        'delivery_hour': deliveryHour,
        'timezone': timezone,
      };
}

@immutable
class VeilleConfigPatchRequest {
  final String? frequency;
  final int? dayOfWeek;
  final int? deliveryHour;
  final String? timezone;
  final String? status;

  const VeilleConfigPatchRequest({
    this.frequency,
    this.dayOfWeek,
    this.deliveryHour,
    this.timezone,
    this.status,
  });

  Map<String, dynamic> toJson() => {
        if (frequency != null) 'frequency': frequency,
        if (dayOfWeek != null) 'day_of_week': dayOfWeek,
        if (deliveryHour != null) 'delivery_hour': deliveryHour,
        if (timezone != null) 'timezone': timezone,
        if (status != null) 'status': status,
      };
}
