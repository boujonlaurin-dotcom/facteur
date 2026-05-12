import 'package:flutter/foundation.dart';

@immutable
class VeilleDeliveryArticle {
  final String contentId;
  final String sourceId;
  final String title;
  final String url;
  final String excerpt;
  final DateTime publishedAt;

  const VeilleDeliveryArticle({
    required this.contentId,
    required this.sourceId,
    required this.title,
    required this.url,
    required this.excerpt,
    required this.publishedAt,
  });

  factory VeilleDeliveryArticle.fromJson(Map<String, dynamic> json) {
    return VeilleDeliveryArticle(
      contentId: json['content_id'] as String,
      sourceId: json['source_id'] as String,
      title: json['title'] as String,
      url: json['url'] as String,
      excerpt: (json['excerpt'] as String?) ?? '',
      publishedAt: DateTime.parse(json['published_at'] as String),
    );
  }
}

@immutable
class VeilleDeliveryItem {
  final String clusterId;
  final String title;
  final List<VeilleDeliveryArticle> articles;
  final String whyItMatters;

  const VeilleDeliveryItem({
    required this.clusterId,
    required this.title,
    required this.articles,
    required this.whyItMatters,
  });

  factory VeilleDeliveryItem.fromJson(Map<String, dynamic> json) {
    final raw = (json['articles'] as List?) ?? const [];
    return VeilleDeliveryItem(
      clusterId: json['cluster_id'] as String,
      title: (json['title'] as String?) ?? '',
      articles: raw
          .whereType<Map<String, dynamic>>()
          .map(VeilleDeliveryArticle.fromJson)
          .toList(),
      whyItMatters: (json['why_it_matters'] as String?) ?? '',
    );
  }
}

enum VeilleGenerationState { pending, running, succeeded, failed }

VeilleGenerationState veilleGenerationStateFrom(String value) {
  return VeilleGenerationState.values.firstWhere(
    (s) => s.name == value,
    orElse: () => VeilleGenerationState.pending,
  );
}

@immutable
class VeilleDeliveryListItem {
  final String id;
  final String veilleConfigId;
  final DateTime targetDate;
  final VeilleGenerationState generationState;
  final int itemCount;
  final DateTime? generatedAt;
  final DateTime createdAt;

  const VeilleDeliveryListItem({
    required this.id,
    required this.veilleConfigId,
    required this.targetDate,
    required this.generationState,
    required this.itemCount,
    required this.generatedAt,
    required this.createdAt,
  });

  factory VeilleDeliveryListItem.fromJson(Map<String, dynamic> json) {
    return VeilleDeliveryListItem(
      id: json['id'] as String,
      veilleConfigId: json['veille_config_id'] as String,
      targetDate: DateTime.parse(json['target_date'] as String),
      generationState:
          veilleGenerationStateFrom(json['generation_state'] as String),
      itemCount: (json['item_count'] as num?)?.toInt() ?? 0,
      generatedAt: json['generated_at'] != null
          ? DateTime.parse(json['generated_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

@immutable
class VeilleDeliveryResponse {
  final String id;
  final String veilleConfigId;
  final DateTime targetDate;
  final List<VeilleDeliveryItem> items;
  final VeilleGenerationState generationState;
  final int attempts;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final String? lastError;
  final int version;
  final DateTime? generatedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const VeilleDeliveryResponse({
    required this.id,
    required this.veilleConfigId,
    required this.targetDate,
    required this.items,
    required this.generationState,
    required this.attempts,
    required this.startedAt,
    required this.finishedAt,
    required this.lastError,
    required this.version,
    required this.generatedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory VeilleDeliveryResponse.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List?) ?? const [];
    return VeilleDeliveryResponse(
      id: json['id'] as String,
      veilleConfigId: json['veille_config_id'] as String,
      targetDate: DateTime.parse(json['target_date'] as String),
      items: rawItems
          .whereType<Map<String, dynamic>>()
          .map(VeilleDeliveryItem.fromJson)
          .toList(),
      generationState:
          veilleGenerationStateFrom(json['generation_state'] as String),
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      startedAt: json['started_at'] != null
          ? DateTime.parse(json['started_at'] as String)
          : null,
      finishedAt: json['finished_at'] != null
          ? DateTime.parse(json['finished_at'] as String)
          : null,
      lastError: json['last_error'] as String?,
      version: (json['version'] as num?)?.toInt() ?? 1,
      generatedAt: json['generated_at'] != null
          ? DateTime.parse(json['generated_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

@immutable
class VeilleGenerateFirstResponse {
  final String deliveryId;
  final int estimatedSeconds;

  const VeilleGenerateFirstResponse({
    required this.deliveryId,
    required this.estimatedSeconds,
  });

  factory VeilleGenerateFirstResponse.fromJson(Map<String, dynamic> json) {
    return VeilleGenerateFirstResponse(
      deliveryId: json['delivery_id'] as String,
      estimatedSeconds: (json['estimated_seconds'] as num?)?.toInt() ?? 60,
    );
  }
}

@immutable
class VeilleSourceExample {
  final String title;
  final String url;
  final DateTime? publishedAt;
  final String excerpt;

  const VeilleSourceExample({
    required this.title,
    required this.url,
    required this.publishedAt,
    required this.excerpt,
  });

  factory VeilleSourceExample.fromJson(Map<String, dynamic> json) {
    return VeilleSourceExample(
      title: json['title'] as String,
      url: json['url'] as String,
      publishedAt: json['published_at'] != null
          ? DateTime.parse(json['published_at'] as String)
          : null,
      excerpt: (json['excerpt'] as String?) ?? '',
    );
  }
}
