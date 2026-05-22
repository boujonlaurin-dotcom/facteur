import 'package:flutter/foundation.dart';

/// DTOs miroir de `packages/api/app/schemas/veille.py` (réponses + bodies).
///
/// Story 23.1 PR-2 a retiré `frequency`/`day_of_week`/`delivery_hour`/`timezone`/
/// `last_delivered_at`/`next_scheduled_at` (scheduler async drop) et ajouté
/// `keywords[]` (angles libres saisis par l'utilisateur).

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
class VeilleKeywordDto {
  final String id;
  final String keyword;
  final int position;

  const VeilleKeywordDto({
    required this.id,
    required this.keyword,
    required this.position,
  });

  factory VeilleKeywordDto.fromJson(Map<String, dynamic> json) {
    return VeilleKeywordDto(
      id: json['id'] as String,
      keyword: json['keyword'] as String,
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
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<VeilleTopicDto> topics;
  final List<VeilleSourceDto> sources;
  final List<VeilleKeywordDto> keywords;
  final String? purpose;
  final String? editorialBrief;
  final String? presetId;

  const VeilleConfigDto({
    required this.id,
    required this.userId,
    required this.themeId,
    required this.themeLabel,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.topics,
    required this.sources,
    required this.keywords,
    this.purpose,
    this.editorialBrief,
    this.presetId,
  });

  factory VeilleConfigDto.fromJson(Map<String, dynamic> json) {
    return VeilleConfigDto(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      themeId: json['theme_id'] as String,
      themeLabel: json['theme_label'] as String,
      status: json['status'] as String,
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
      keywords: ((json['keywords'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(VeilleKeywordDto.fromJson)
          .toList(),
      purpose: json['purpose'] as String?,
      editorialBrief: json['editorial_brief'] as String?,
      presetId: json['preset_id'] as String?,
    );
  }
}

// ─── Bodies (POST) ────────────────────────────────────────────────────────

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
class VeilleKeywordSelectionRequest {
  final String keyword;
  final int position;

  const VeilleKeywordSelectionRequest({
    required this.keyword,
    this.position = 0,
  });

  Map<String, dynamic> toJson() => {
        'keyword': keyword,
        'position': position,
      };
}

@immutable
class VeilleConfigUpsertRequest {
  final String themeId;
  final String themeLabel;
  final List<VeilleTopicSelectionRequest> topics;
  final List<VeilleSourceSelectionRequest> sourceSelections;
  final List<VeilleKeywordSelectionRequest> keywords;
  final String? purpose;
  final String? editorialBrief;
  final String? presetId;

  const VeilleConfigUpsertRequest({
    required this.themeId,
    required this.themeLabel,
    required this.topics,
    required this.sourceSelections,
    this.keywords = const [],
    this.purpose,
    this.editorialBrief,
    this.presetId,
  });

  Map<String, dynamic> toJson() => {
        'theme_id': themeId,
        'theme_label': themeLabel,
        'topics': topics.map((t) => t.toJson()).toList(),
        'source_selections': sourceSelections.map((s) => s.toJson()).toList(),
        'keywords': keywords.map((k) => k.toJson()).toList(),
        'purpose': purpose,
        'editorial_brief': editorialBrief,
        'preset_id': presetId,
      };
}

// ─── Suggesters LLM (Story 23.3) ─────────────────────────────────────────────

@immutable
class VeilleSuggestAnglesRequest {
  final String themeId;
  final String themeLabel;
  final String brief;

  const VeilleSuggestAnglesRequest({
    required this.themeId,
    required this.themeLabel,
    this.brief = '',
  });

  Map<String, dynamic> toJson() => {
        'theme_id': themeId,
        'theme_label': themeLabel,
        'brief': brief,
      };
}

@immutable
class VeilleAngleSuggestionDto {
  final String title;
  final List<String> keywords;
  final String? reason;

  const VeilleAngleSuggestionDto({
    required this.title,
    required this.keywords,
    this.reason,
  });

  factory VeilleAngleSuggestionDto.fromJson(Map<String, dynamic> json) {
    return VeilleAngleSuggestionDto(
      title: json['title'] as String,
      keywords: ((json['keywords'] as List?) ?? const [])
          .whereType<String>()
          .toList(),
      reason: json['reason'] as String?,
    );
  }

  VeilleAngleSuggestionDto copyWith({
    String? title,
    List<String>? keywords,
    Object? reason = _AngleSentinel.value,
  }) {
    return VeilleAngleSuggestionDto(
      title: title ?? this.title,
      keywords: keywords ?? this.keywords,
      reason: reason == _AngleSentinel.value ? this.reason : reason as String?,
    );
  }
}

enum _AngleSentinel { value }

@immutable
class VeilleSuggestAnglesResponse {
  final List<VeilleAngleSuggestionDto> angles;

  const VeilleSuggestAnglesResponse({required this.angles});

  factory VeilleSuggestAnglesResponse.fromJson(Map<String, dynamic> json) {
    return VeilleSuggestAnglesResponse(
      angles: ((json['angles'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(VeilleAngleSuggestionDto.fromJson)
          .toList(),
    );
  }
}

@immutable
class VeilleSuggestSourcesRequest {
  final String themeId;
  final String themeLabel;
  final String brief;
  final List<String> angles;
  final List<String> keywords;

  const VeilleSuggestSourcesRequest({
    required this.themeId,
    required this.themeLabel,
    this.brief = '',
    this.angles = const [],
    this.keywords = const [],
  });

  Map<String, dynamic> toJson() => {
        'theme_id': themeId,
        'theme_label': themeLabel,
        'brief': brief,
        'angles': angles,
        'keywords': keywords,
      };
}

@immutable
class VeilleSourceSuggestionDto {
  final String name;
  final String url;
  final String? why;
  final double relevanceScore;

  const VeilleSourceSuggestionDto({
    required this.name,
    required this.url,
    this.why,
    required this.relevanceScore,
  });

  factory VeilleSourceSuggestionDto.fromJson(Map<String, dynamic> json) {
    return VeilleSourceSuggestionDto(
      name: json['name'] as String,
      url: json['url'] as String,
      why: json['why'] as String?,
      relevanceScore: (json['relevance_score'] as num).toDouble(),
    );
  }
}

@immutable
class VeilleSuggestSourcesResponse {
  final List<VeilleSourceSuggestionDto> sources;

  const VeilleSuggestSourcesResponse({required this.sources});

  factory VeilleSuggestSourcesResponse.fromJson(Map<String, dynamic> json) {
    return VeilleSuggestSourcesResponse(
      sources: ((json['sources'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(VeilleSourceSuggestionDto.fromJson)
          .toList(),
    );
  }
}
