import '../../sources/models/source_model.dart';

enum ContentType {
  article,
  video,
  audio,
  youtube,
}

enum ContentStatus {
  unseen,
  seen,
  consumed,
}

class RecommendationReason {
  final String label;
  final double confidence;

  RecommendationReason({
    required this.label,
    required this.confidence,
  });

  factory RecommendationReason.fromJson(Map<String, dynamic> json) {
    return RecommendationReason(
      label: json['label'] as String,
      confidence: (json['confidence'] as num).toDouble(),
    );
  }
}

enum HiddenReason {
  source,
  topic,
}

class Content {
  final String id;
  final String title;
  final String url;
  final String? thumbnailUrl;
  final String? description;
  final String? htmlContent; // Story 5.2: In-App Reading Mode
  final String? audioUrl; // Story 5.2: In-App Reading Mode
  final ContentType contentType;
  final int? durationSeconds;
  final DateTime publishedAt;
  final Source source;
  final ContentStatus status;
  final bool isSaved;
  final bool isHidden;
  final RecommendationReason? recommendationReason;

  Content({
    required this.id,
    required this.title,
    required this.url,
    this.thumbnailUrl,
    this.description,
    this.htmlContent,
    this.audioUrl,
    required this.contentType,
    this.durationSeconds,
    required this.publishedAt,
    required this.source,
    this.status = ContentStatus.unseen,
    this.isSaved = false,
    this.isHidden = false,
    this.recommendationReason,
  });

  factory Content.fromJson(Map<String, dynamic> json) {
    return Content(
      id: json['id'] as String,
      title: json['title'] as String,
      url: json['url'] as String,
      thumbnailUrl: json['thumbnail_url'] as String?,
      description: json['description'] as String?,
      htmlContent: json['html_content'] as String?,
      audioUrl: json['audio_url'] as String?,
      contentType: ContentType.values.firstWhere(
        (e) => e.name == (json['content_type'] as String).toLowerCase(),
        orElse: () => ContentType.article,
      ),
      durationSeconds: json['duration_seconds'] as int?,
      publishedAt: DateTime.parse(json['published_at'] as String),
      source: Source.fromJson(json['source'] as Map<String, dynamic>),
      status: ContentStatus.values.firstWhere(
        (e) => e.name == (json['status'] as String).toLowerCase(),
        orElse: () => ContentStatus.unseen,
      ),
      isSaved: json['is_saved'] as bool? ?? false,
      isHidden: json['is_hidden'] as bool? ?? false,
      recommendationReason: json['recommendation_reason'] != null
          ? RecommendationReason.fromJson(
              json['recommendation_reason'] as Map<String, dynamic>)
          : null,
    );
  }

  Content copyWith({
    String? id,
    String? title,
    String? url,
    String? thumbnailUrl,
    String? description,
    String? htmlContent,
    String? audioUrl,
    ContentType? contentType,
    int? durationSeconds,
    DateTime? publishedAt,
    Source? source,
    ContentStatus? status,
    bool? isSaved,
    bool? isHidden,
    RecommendationReason? recommendationReason,
  }) {
    return Content(
      id: id ?? this.id,
      title: title ?? this.title,
      url: url ?? this.url,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      description: description ?? this.description,
      htmlContent: htmlContent ?? this.htmlContent,
      audioUrl: audioUrl ?? this.audioUrl,
      contentType: contentType ?? this.contentType,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      publishedAt: publishedAt ?? this.publishedAt,
      source: source ?? this.source,
      status: status ?? this.status,
      isSaved: isSaved ?? this.isSaved,
      isHidden: isHidden ?? this.isHidden,
      recommendationReason: recommendationReason ?? this.recommendationReason,
    );
  }

  /// Story 5.2: Check if content has enough data for in-app reading
  /// DEPRECATED (Story 4.3b): This logic is deprecated and always returns false.
  /// We now always use WebView to display the full article to avoid ads/cookie banners.
  /// This may be re-implemented in the future when ad/cookie bypass becomes a priority.
  @Deprecated('Always returns false. Use WebView for all content types.')
  bool get hasInAppContent {
    return false; // DEPRECATED: Always use WebView

    // Original logic (kept for reference):
    // switch (contentType) {
    //   case ContentType.article:
    //     return (htmlContent?.length ?? 0) > 100;
    //   case ContentType.audio:
    //     return audioUrl != null && audioUrl!.isNotEmpty;
    //   case ContentType.youtube:
    //   case ContentType.video:
    //     return true;
    // }
  }

  /// Story 8.0: Get the topic used for progression (granularity layer)
  String? get progressionTopic {
    // V0: Use source theme as the topic
    // Future: Use specific tags or categories
    if (source.theme != null && source.theme!.isNotEmpty) {
      return source.getThemeLabel();
    }
    return null;
  }
}

class Pagination {
  final int page;
  final int perPage;
  final int total;
  final bool hasNext;

  Pagination({
    required this.page,
    required this.perPage,
    required this.total,
    required this.hasNext,
  });

  factory Pagination.fromJson(Map<String, dynamic> json) {
    return Pagination(
      page: json['page'] as int? ?? 1,
      perPage: json['per_page'] as int? ?? 20,
      total: json['total'] as int? ?? 0,
      hasNext: json['has_next'] as bool? ?? false,
    );
  }
}

class DailyTop3Item {
  final int rank;
  final String reason;
  final bool isConsumed;
  final Content content;

  DailyTop3Item({
    required this.rank,
    required this.reason,
    required this.isConsumed,
    required this.content,
  });

  factory DailyTop3Item.fromJson(Map<String, dynamic> json) {
    return DailyTop3Item(
      rank: json['rank'] as int,
      reason: json['reason'] as String,
      isConsumed: json['consumed'] as bool,
      content: Content.fromJson(json['content'] as Map<String, dynamic>),
    );
  }
}

class FeedResponse {
  final List<Content> items;
  final List<DailyTop3Item> briefing;
  final Pagination pagination;

  FeedResponse({
    required this.items,
    this.briefing = const [],
    required this.pagination,
  });

  factory FeedResponse.fromJson(Map<String, dynamic> json) {
    return FeedResponse(
      items: (json['items'] as List<dynamic>?)
              ?.map((e) => Content.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      briefing: (json['briefing'] as List<dynamic>?)
              ?.map((e) => DailyTop3Item.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      pagination: json['pagination'] != null
          ? Pagination.fromJson(json['pagination'] as Map<String, dynamic>)
          : Pagination(page: 1, perPage: 20, total: 0, hasNext: false),
    );
  }
}
