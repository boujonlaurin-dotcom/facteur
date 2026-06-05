import 'package:flutter/foundation.dart';

/// DTOs miroir de `packages/api/app/schemas/veille.py` (réponses + bodies).
///
/// Story 23.1 PR-2 a retiré `frequency`/`day_of_week`/`delivery_hour`/`timezone`/
/// `last_delivered_at`/`next_scheduled_at` (scheduler async drop) et ajouté
/// `keywords[]` (angles libres saisis par l'utilisateur).
///
/// Veille micro-ajustements : `POST /veille/suggest/sources` est reconnecté
/// pour proposer des candidats niche non ingérés avant submit.
///
/// Veille C3 (PR-3) : `VeilleAngleSuggestionDto` / `VeilleSuggestAnglesResponse`
/// ré-introduits — `POST /veille/suggest/angles` est actif (suggestion d'angles
/// LLM = titre + grappe de mots-clés éditable au Step 2).

@immutable
class VeilleTopicDto {
  final String id;
  final String topicId;
  final String label;
  final String kind;
  final String? reason;
  final int position;

  /// Grappe de mots-clés de l'angle (round-trip avec le backend).
  final List<String> keywords;

  const VeilleTopicDto({
    required this.id,
    required this.topicId,
    required this.label,
    required this.kind,
    required this.reason,
    required this.position,
    this.keywords = const [],
  });

  factory VeilleTopicDto.fromJson(Map<String, dynamic> json) {
    return VeilleTopicDto(
      id: json['id'] as String,
      topicId: json['topic_id'] as String,
      label: json['label'] as String,
      kind: json['kind'] as String,
      reason: json['reason'] as String?,
      position: (json['position'] as num?)?.toInt() ?? 0,
      keywords: ((json['keywords'] as List?) ?? const [])
          .map((e) => e as String)
          .toList(),
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
  // Santé du flux (refonte curation) : date du dernier article ingéré +
  // nombre d'articles sur la fenêtre Bloc A (30 j). Alimentent le badge
  // « flux inactif / aucun article récent » côté config. Nullable/0 par défaut
  // (backend pré-refonte → champs absents).
  final DateTime? lastArticleAt;
  final int recentArticleCount;

  const VeilleSourceDto({
    required this.id,
    required this.source,
    required this.kind,
    required this.why,
    required this.position,
    this.lastArticleAt,
    this.recentArticleCount = 0,
  });

  factory VeilleSourceDto.fromJson(Map<String, dynamic> json) {
    return VeilleSourceDto(
      id: json['id'] as String,
      source: VeilleSourceLiteDto.fromJson(
        json['source'] as Map<String, dynamic>,
      ),
      kind: json['kind'] as String,
      why: json['why'] as String?,
      position: (json['position'] as num?)?.toInt() ?? 0,
      lastArticleAt: json['last_article_at'] != null
          ? DateTime.tryParse(json['last_article_at'] as String)
          : null,
      recentArticleCount: (json['recent_article_count'] as num?)?.toInt() ?? 0,
    );
  }

  /// Santé éditoriale du flux pour le badge config. `null` → flux sain (assez
  /// d'articles récents). Sinon un libellé court à afficher en avertissement.
  String? get healthWarning {
    if (recentArticleCount > 0) return null;
    if (lastArticleAt == null) return 'aucun article';
    final days = DateTime.now().difference(lastArticleAt!).inDays;
    if (days >= 30) return 'flux inactif';
    return 'aucun article récent';
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
class VeilleUnconnectedSourceDto {
  final String url;
  final String reason;
  final String? clientSlug;
  final String? name;

  const VeilleUnconnectedSourceDto({
    required this.url,
    required this.reason,
    this.clientSlug,
    this.name,
  });

  factory VeilleUnconnectedSourceDto.fromJson(Map<String, dynamic> json) {
    return VeilleUnconnectedSourceDto(
      url: json['url'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
      clientSlug: json['client_slug'] as String?,
      name: json['name'] as String?,
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

  /// Sources niche dont le flux RSS n'a pas pu être détecté lors de l'upsert.
  /// Peuplé uniquement par la réponse de `POST /veille/config` ; vide sur GET.
  final List<VeilleUnconnectedSourceDto> unconnectedSources;

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
    this.unconnectedSources = const [],
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
      unconnectedSources: ((json['unconnected_sources'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(VeilleUnconnectedSourceDto.fromJson)
          .toList(),
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

  /// Grappe de mots-clés de l'angle — pilote le scoring côté backend.
  final List<String> keywords;

  const VeilleTopicSelectionRequest({
    required this.topicId,
    required this.label,
    required this.kind,
    this.reason,
    this.position = 0,
    this.keywords = const [],
  });

  Map<String, dynamic> toJson() => {
    'topic_id': topicId,
    'label': label,
    'kind': kind,
    if (reason != null) 'reason': reason,
    'position': position,
    'keywords': keywords,
  };
}

@immutable
class VeilleNicheCandidateRequest {
  final String? clientSlug;
  final String name;
  final String url;
  final String? why;

  const VeilleNicheCandidateRequest({
    this.clientSlug,
    required this.name,
    required this.url,
    this.why,
  });

  Map<String, dynamic> toJson() => {
    if (clientSlug != null) 'client_slug': clientSlug,
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

  Map<String, dynamic> toJson() => {'keyword': keyword, 'position': position};
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

// ─── Suggestion d'angles LLM (POST /veille/suggest/angles) ──────────────────

/// Un angle suggéré par le LLM : un titre éditorial + sa grappe de mots-clés
/// (pilote le scoring) + une raison courte. Miroir de `VeilleAngleSuggestion`
/// (`packages/api/app/schemas/veille.py`).
@immutable
class VeilleAngleSuggestionDto {
  final String title;
  final List<String> keywords;
  final String? reason;

  const VeilleAngleSuggestionDto({
    required this.title,
    this.keywords = const [],
    this.reason,
  });

  factory VeilleAngleSuggestionDto.fromJson(Map<String, dynamic> json) {
    return VeilleAngleSuggestionDto(
      title: json['title'] as String,
      keywords: ((json['keywords'] as List?) ?? const [])
          .map((e) => e as String)
          .toList(),
      reason: json['reason'] as String?,
    );
  }
}

/// Réponse de `POST /veille/suggest/angles`. Miroir de
/// `VeilleSuggestAnglesResponse` côté backend.
@immutable
class VeilleSuggestAnglesResponse {
  final List<VeilleAngleSuggestionDto> angles;

  const VeilleSuggestAnglesResponse({this.angles = const []});

  factory VeilleSuggestAnglesResponse.fromJson(Map<String, dynamic> json) {
    return VeilleSuggestAnglesResponse(
      angles: ((json['angles'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(VeilleAngleSuggestionDto.fromJson)
          .toList(),
    );
  }
}

// ─── Résolution sujet local Veille (POST /veille/resolve/topic) ─────────────

@immutable
class VeilleResolvedTopicDto {
  final String label;
  final String topicId;
  final List<String> keywords;
  final String description;
  final Map<String, String?> metadata;

  const VeilleResolvedTopicDto({
    required this.label,
    required this.topicId,
    this.keywords = const [],
    this.description = '',
    this.metadata = const {},
  });

  factory VeilleResolvedTopicDto.fromJson(Map<String, dynamic> json) {
    final rawMeta = json['metadata'];
    return VeilleResolvedTopicDto(
      label: json['label'] as String,
      topicId: json['topic_id'] as String,
      keywords: ((json['keywords'] as List?) ?? const [])
          .map((e) => e as String)
          .toList(),
      description: (json['description'] as String?) ?? '',
      metadata: rawMeta is Map
          ? rawMeta.map(
              (key, value) => MapEntry(key.toString(), value?.toString()),
            )
          : const {},
    );
  }
}

// ─── Suggestion sources LLM (POST /veille/suggest/sources) ──────────────────

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
      relevanceScore: (json['relevance_score'] as num?)?.toDouble() ?? 0,
    );
  }
}

@immutable
class VeilleSuggestSourcesResponse {
  final List<VeilleSourceSuggestionDto> sources;

  const VeilleSuggestSourcesResponse({this.sources = const []});

  factory VeilleSuggestSourcesResponse.fromJson(Map<String, dynamic> json) {
    return VeilleSuggestSourcesResponse(
      sources: ((json['sources'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(VeilleSourceSuggestionDto.fromJson)
          .toList(),
    );
  }
}

// ─── Résolution batch sources candidates (POST /veille/sources/resolve-candidates)

@immutable
class VeilleResolveSourceCandidateRequest {
  final String clientSlug;
  final String name;
  final String url;
  final String? why;

  const VeilleResolveSourceCandidateRequest({
    required this.clientSlug,
    required this.name,
    required this.url,
    this.why,
  });

  Map<String, dynamic> toJson() => {
    'client_slug': clientSlug,
    'name': name,
    'url': url,
    if (why != null) 'why': why,
  };
}

@immutable
class VeilleResolvedSourceCandidateDto {
  final String clientSlug;
  final String sourceId;
  final String name;
  final String url;
  final String feedUrl;
  final String? logoUrl;
  final String? description;

  const VeilleResolvedSourceCandidateDto({
    required this.clientSlug,
    required this.sourceId,
    required this.name,
    required this.url,
    required this.feedUrl,
    this.logoUrl,
    this.description,
  });

  factory VeilleResolvedSourceCandidateDto.fromJson(Map<String, dynamic> json) {
    return VeilleResolvedSourceCandidateDto(
      clientSlug: json['client_slug'] as String,
      sourceId: json['source_id'] as String,
      name: json['name'] as String,
      url: json['url'] as String,
      feedUrl: json['feed_url'] as String,
      logoUrl: json['logo_url'] as String?,
      description: json['description'] as String?,
    );
  }
}

@immutable
class VeilleFailedSourceCandidateDto {
  final String clientSlug;
  final String name;
  final String url;
  final String reason;

  const VeilleFailedSourceCandidateDto({
    required this.clientSlug,
    required this.name,
    required this.url,
    required this.reason,
  });

  factory VeilleFailedSourceCandidateDto.fromJson(Map<String, dynamic> json) {
    return VeilleFailedSourceCandidateDto(
      clientSlug: json['client_slug'] as String,
      name: json['name'] as String? ?? '',
      url: json['url'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
    );
  }
}

@immutable
class VeilleResolveSourceCandidatesResponseDto {
  final List<VeilleResolvedSourceCandidateDto> resolved;
  final List<VeilleFailedSourceCandidateDto> failed;

  const VeilleResolveSourceCandidatesResponseDto({
    this.resolved = const [],
    this.failed = const [],
  });

  factory VeilleResolveSourceCandidatesResponseDto.fromJson(
    Map<String, dynamic> json,
  ) {
    return VeilleResolveSourceCandidatesResponseDto(
      resolved: ((json['resolved'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(VeilleResolvedSourceCandidateDto.fromJson)
          .toList(),
      failed: ((json['failed'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(VeilleFailedSourceCandidateDto.fromJson)
          .toList(),
    );
  }
}
