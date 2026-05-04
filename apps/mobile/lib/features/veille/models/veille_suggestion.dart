import 'package:flutter/foundation.dart';

@immutable
class VeilleTopicSuggestion {
  final String topicId;
  final String label;
  final String? reason;

  const VeilleTopicSuggestion({
    required this.topicId,
    required this.label,
    this.reason,
  });

  factory VeilleTopicSuggestion.fromJson(Map<String, dynamic> json) {
    return VeilleTopicSuggestion(
      topicId: json['topic_id'] as String,
      label: json['label'] as String,
      reason: json['reason'] as String?,
    );
  }
}

@immutable
class VeilleSourceSuggestion {
  final String sourceId;
  final String name;
  final String url;
  final String feedUrl;
  final String theme;
  final String? why;
  final bool isAlreadyFollowed;
  final double? relevanceScore;

  const VeilleSourceSuggestion({
    required this.sourceId,
    required this.name,
    required this.url,
    required this.feedUrl,
    required this.theme,
    this.why,
    this.isAlreadyFollowed = false,
    this.relevanceScore,
  });

  factory VeilleSourceSuggestion.fromJson(Map<String, dynamic> json) {
    final score = json['relevance_score'];
    return VeilleSourceSuggestion(
      sourceId: json['source_id'] as String,
      name: json['name'] as String,
      url: json['url'] as String,
      feedUrl: json['feed_url'] as String,
      theme: json['theme'] as String,
      why: json['why'] as String?,
      isAlreadyFollowed: (json['is_already_followed'] as bool?) ?? false,
      relevanceScore: score is num ? score.toDouble() : null,
    );
  }
}

@immutable
class VeilleSourceSuggestionsResponse {
  final List<VeilleSourceSuggestion> sources;

  const VeilleSourceSuggestionsResponse({required this.sources});

  factory VeilleSourceSuggestionsResponse.fromJson(Map<String, dynamic> json) {
    return VeilleSourceSuggestionsResponse(
      sources: ((json['sources'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(VeilleSourceSuggestion.fromJson)
          .toList(),
    );
  }
}
