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

  const VeilleSourceSuggestion({
    required this.sourceId,
    required this.name,
    required this.url,
    required this.feedUrl,
    required this.theme,
    this.why,
  });

  factory VeilleSourceSuggestion.fromJson(Map<String, dynamic> json) {
    return VeilleSourceSuggestion(
      sourceId: json['source_id'] as String,
      name: json['name'] as String,
      url: json['url'] as String,
      feedUrl: json['feed_url'] as String,
      theme: json['theme'] as String,
      why: json['why'] as String?,
    );
  }
}

@immutable
class VeilleSourceSuggestionsResponse {
  final List<VeilleSourceSuggestion> followed;
  final List<VeilleSourceSuggestion> niche;

  const VeilleSourceSuggestionsResponse({
    required this.followed,
    required this.niche,
  });

  factory VeilleSourceSuggestionsResponse.fromJson(Map<String, dynamic> json) {
    return VeilleSourceSuggestionsResponse(
      followed: ((json['followed'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(VeilleSourceSuggestion.fromJson)
          .toList(),
      niche: ((json['niche'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(VeilleSourceSuggestion.fromJson)
          .toList(),
    );
  }
}
