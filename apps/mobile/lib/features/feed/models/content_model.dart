import '../../../config/topic_labels.dart';
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

/// Contribution d'un facteur au score de recommandation.
class ScoreContribution {
  final String label;
  final double points;
  final bool isPositive;
  final String? pillar;

  ScoreContribution({
    required this.label,
    required this.points,
    this.isPositive = true,
    this.pillar,
  });

  factory ScoreContribution.fromJson(Map<String, dynamic> json) {
    return ScoreContribution(
      label: (json['label'] as String?) ?? 'Facteur',
      points: (json['points'] as num?)?.toDouble() ?? 0.0,
      isPositive: (json['is_positive'] as bool?) ?? true,
      pillar: json['pillar'] as String?,
    );
  }
}

/// Raison de la recommandation avec breakdown détaillé.
class RecommendationReason {
  final String label;
  final double scoreTotal;
  final List<ScoreContribution> breakdown;

  RecommendationReason({
    required this.label,
    this.scoreTotal = 0.0,
    this.breakdown = const [],
  });

  factory RecommendationReason.fromJson(Map<String, dynamic> json) {
    final breakdownJson = json['breakdown'];
    return RecommendationReason(
      label: (json['label'] as String?) ?? 'Recommandé',
      scoreTotal: (json['score_total'] as num?)?.toDouble() ?? 0.0,
      breakdown: (breakdownJson is List)
          ? breakdownJson
              .whereType<Map<String, dynamic>>()
              .map((e) => ScoreContribution.fromJson(e))
              .toList()
          : const [],
    );
  }
}

enum HiddenReason {
  source,
  topic,
}

class ContentEntity {
  final String text;
  final String label;

  ContentEntity({required this.text, required this.label});

  factory ContentEntity.fromJson(Map<String, dynamic> json) {
    return ContentEntity(
      text: (json['text'] as String?) ?? '',
      label: (json['label'] as String?) ?? '',
    );
  }
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
  final bool isLiked;
  final bool isHidden;
  final bool isPaid;
  final List<String> topics;
  final List<ContentEntity> entities;
  final RecommendationReason? recommendationReason;
  final int readingProgress; // 0-100 scroll depth percentage
  final String? noteText;
  final DateTime? noteUpdatedAt;
  final bool isFollowedSource; // Feed fallback: source suivie par l'utilisateur

  // Epic 11: Cluster fields (populated by FeedRepository when clusters are present)
  final String? clusterTopic;
  final int clusterHiddenCount;
  final List<String> clusterHiddenIds;
  final List<Content> clusterHiddenArticles;

  // Epic 12: Source overflow (populated by FeedRepository from diversification)
  final int sourceOverflowCount;

  // Topic overflow (populated by FeedRepository from topic regroupement Phase 2)
  final int topicOverflowCount;
  final String? topicOverflowLabel;
  final String? topicOverflowKey;
  final String? topicOverflowType; // "topic" or "theme"
  final List<String> topicOverflowHiddenIds;

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
    this.isLiked = false,
    this.isHidden = false,
    this.isPaid = false,
    this.topics = const [],
    this.entities = const [],
    this.recommendationReason,
    this.readingProgress = 0,
    this.noteText,
    this.noteUpdatedAt,
    this.isFollowedSource = false,
    this.clusterTopic,
    this.clusterHiddenCount = 0,
    this.clusterHiddenIds = const [],
    this.clusterHiddenArticles = const [],
    this.sourceOverflowCount = 0,
    this.topicOverflowCount = 0,
    this.topicOverflowLabel,
    this.topicOverflowKey,
    this.topicOverflowType,
    this.topicOverflowHiddenIds = const [],
  });

  bool get isVideo => contentType == ContentType.youtube || contentType == ContentType.video;

  bool get hasNote => noteText != null && noteText!.isNotEmpty;

  /// Reading badge label based on reading_progress.
  /// Returns null if article hasn't been interacted with.
  /// readingProgress > 0 always takes priority over consumed status,
  /// because the 30s timer can mark consumed before meaningful scroll.
  String? get readingLabel {
    if (status == ContentStatus.unseen && readingProgress == 0) return null;

    // Video-specific labels
    if (contentType == ContentType.youtube || contentType == ContentType.video) {
      if (readingProgress >= 90) return 'Vu jusqu\'au bout';
      if (readingProgress >= 25) return 'Vu en partie';
      // Consumed via timer but no progress tracking
      if (status == ContentStatus.consumed) return 'Vu en partie';
      return null;
    }

    // Article labels
    if (readingProgress >= 90) return 'Lu jusqu\'au bout';
    if (readingProgress >= 30) return 'Lu';
    if (readingProgress > 0) return 'Parcouru';
    // Consumed via 30s timer but no scroll tracking (e.g. partial content)
    if (status == ContentStatus.consumed) return 'Lu';
    return null;
  }

  /// Returns a copy with note fields explicitly set to null.
  /// Needed because copyWith uses ?? which can't set nullable fields to null.
  Content clearNote() {
    return Content(
      id: id,
      title: title,
      url: url,
      thumbnailUrl: thumbnailUrl,
      description: description,
      htmlContent: htmlContent,
      audioUrl: audioUrl,
      contentType: contentType,
      durationSeconds: durationSeconds,
      publishedAt: publishedAt,
      source: source,
      status: status,
      isSaved: isSaved,
      isLiked: isLiked,
      isHidden: isHidden,
      isPaid: isPaid,
      topics: topics,
      entities: entities,
      recommendationReason: recommendationReason,
      readingProgress: readingProgress,
      noteText: null,
      noteUpdatedAt: null,
      isFollowedSource: isFollowedSource,
      clusterTopic: clusterTopic,
      clusterHiddenCount: clusterHiddenCount,
      clusterHiddenIds: clusterHiddenIds,
      clusterHiddenArticles: clusterHiddenArticles,
      sourceOverflowCount: sourceOverflowCount,
      topicOverflowCount: topicOverflowCount,
      topicOverflowLabel: topicOverflowLabel,
      topicOverflowKey: topicOverflowKey,
      topicOverflowType: topicOverflowType,
      topicOverflowHiddenIds: topicOverflowHiddenIds,
    );
  }

  factory Content.fromJson(Map<String, dynamic> json) {
    try {
      final sourceJson = json['source'];
      final recJson = json['recommendation_reason'];

      return Content(
        id: (json['id'] as String?) ?? '',
        title: (json['title'] as String?) ?? 'Sans titre',
        url: (json['url'] as String?) ?? '',
        thumbnailUrl: json['thumbnail_url'] as String?,
        description: json['description'] as String?,
        htmlContent: json['html_content'] as String?,
        audioUrl: json['audio_url'] as String?,
        contentType: ContentType.values.firstWhere(
          (e) => e.name == (json['content_type'] as String?)?.toLowerCase(),
          orElse: () => ContentType.article,
        ),
        durationSeconds: json['duration_seconds'] as int?,
        publishedAt: DateTime.tryParse(json['published_at'] as String? ?? '') ??
            DateTime.now(),
        source: (sourceJson is Map<String, dynamic>)
            ? Source.fromJson(sourceJson)
            : Source.fallback(),
        status: ContentStatus.values.firstWhere(
          (e) => e.name == (json['status'] as String?)?.toLowerCase(),
          orElse: () => ContentStatus.unseen,
        ),
        isSaved: (json['is_saved'] as bool?) ?? false,
        isLiked: (json['is_liked'] as bool?) ?? false,
        isHidden: (json['is_hidden'] as bool?) ?? false,
        isPaid: (json['is_paid'] as bool?) ?? false,
        topics: (json['topics'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        entities: (json['entities'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .map((e) => ContentEntity.fromJson(e))
                .toList() ??
            const [],
        recommendationReason: (recJson is Map<String, dynamic>)
            ? RecommendationReason.fromJson(recJson)
            : null,
        readingProgress: (json['reading_progress'] as int?) ?? 0,
        noteText: json['note_text'] as String?,
        noteUpdatedAt: json['note_updated_at'] != null
            ? DateTime.tryParse(json['note_updated_at'] as String)
            : null,
        isFollowedSource: (json['is_followed_source'] as bool?) ?? false,
      );
    } catch (e, stack) {
      // ignore: avoid_print
      print('Content.fromJson: [CRITICAL ERROR] Failed to parse: $e\n$stack');
      // On renvoie un objet minimal plutôt que de crash
      return Content(
        id: (json['id'] as String?) ?? 'error',
        title: 'Erreur de chargement',
        url: '',
        contentType: ContentType.article,
        publishedAt: DateTime.now(),
        source: Source.fallback(),
      );
    }
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
    bool? isLiked,
    bool? isHidden,
    bool? isPaid,
    List<String>? topics,
    List<ContentEntity>? entities,
    RecommendationReason? recommendationReason,
    int? readingProgress,
    String? noteText,
    DateTime? noteUpdatedAt,
    bool? isFollowedSource,
    String? clusterTopic,
    int? clusterHiddenCount,
    List<String>? clusterHiddenIds,
    List<Content>? clusterHiddenArticles,
    int? sourceOverflowCount,
    int? topicOverflowCount,
    String? topicOverflowLabel,
    String? topicOverflowKey,
    String? topicOverflowType,
    List<String>? topicOverflowHiddenIds,
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
      isLiked: isLiked ?? this.isLiked,
      isHidden: isHidden ?? this.isHidden,
      isPaid: isPaid ?? this.isPaid,
      topics: topics ?? this.topics,
      entities: entities ?? this.entities,
      recommendationReason: recommendationReason ?? this.recommendationReason,
      readingProgress: readingProgress ?? this.readingProgress,
      noteText: noteText ?? this.noteText,
      noteUpdatedAt: noteUpdatedAt ?? this.noteUpdatedAt,
      isFollowedSource: isFollowedSource ?? this.isFollowedSource,
      clusterTopic: clusterTopic ?? this.clusterTopic,
      clusterHiddenCount: clusterHiddenCount ?? this.clusterHiddenCount,
      clusterHiddenIds: clusterHiddenIds ?? this.clusterHiddenIds,
      clusterHiddenArticles:
          clusterHiddenArticles ?? this.clusterHiddenArticles,
      sourceOverflowCount: sourceOverflowCount ?? this.sourceOverflowCount,
      topicOverflowCount: topicOverflowCount ?? this.topicOverflowCount,
      topicOverflowLabel: topicOverflowLabel ?? this.topicOverflowLabel,
      topicOverflowKey: topicOverflowKey ?? this.topicOverflowKey,
      topicOverflowType: topicOverflowType ?? this.topicOverflowType,
      topicOverflowHiddenIds:
          topicOverflowHiddenIds ?? this.topicOverflowHiddenIds,
    );
  }

  /// Check if content supports in-app reading mode.
  /// Articles always use the native Facteur reader (with fallback CTA to original).
  /// Non-article source types (YouTube, Reddit, podcast) skip the reader entirely.
  /// YouTube/Audio native players will be re-enabled in phase 2.
  bool get hasInAppContent {
    // Non-article sources should never use the in-app reader
    if (source.type == SourceType.youtube ||
        source.type == SourceType.reddit ||
        source.type == SourceType.podcast) {
      return false;
    }
    switch (contentType) {
      case ContentType.article:
        return true; // Native Facteur reader with ArticleReaderWidget
      case ContentType.audio:
      case ContentType.youtube:
      case ContentType.video:
        return false; // Phase 2: re-enable native players
    }
  }

  /// Story 8.0: Get the topic used for progression (granularity layer)
  String? get progressionTopic {
    // Priorité : topics ML granulaires > thème source
    if (topics.isNotEmpty) {
      return getTopicLabel(topics.first);
    }
    // Fallback : thème source (comportement pré-ML)
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

/// Epic 11: A topic cluster grouping related articles in the feed.
class FeedCluster {
  final String topicSlug;
  final String topicName;
  final String representativeId;
  final int hiddenCount;
  final List<String> hiddenIds;

  FeedCluster({
    required this.topicSlug,
    required this.topicName,
    required this.representativeId,
    this.hiddenCount = 0,
    this.hiddenIds = const [],
  });

  factory FeedCluster.fromJson(Map<String, dynamic> json) {
    return FeedCluster(
      topicSlug: (json['topic_slug'] as String?) ?? '',
      topicName: (json['topic_name'] as String?) ?? '',
      representativeId: (json['representative_id'] as String?) ?? '',
      hiddenCount: (json['hidden_count'] as int?) ?? 0,
      hiddenIds: (json['hidden_ids'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }
}

/// Topic overflow from topic-aware regroupement (Phase 2).
class TopicOverflow {
  final String groupType; // "topic" or "theme"
  final String groupKey;
  final String groupLabel;
  final int hiddenCount;
  final List<String> hiddenIds;

  TopicOverflow({
    required this.groupType,
    required this.groupKey,
    required this.groupLabel,
    required this.hiddenCount,
    this.hiddenIds = const [],
  });

  factory TopicOverflow.fromJson(Map<String, dynamic> json) {
    return TopicOverflow(
      groupType: (json['group_type'] as String?) ?? 'theme',
      groupKey: (json['group_key'] as String?) ?? '',
      groupLabel: (json['group_label'] as String?) ?? '',
      hiddenCount: (json['hidden_count'] as int?) ?? 0,
      hiddenIds: (json['hidden_ids'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }
}

/// Epic 12: Source overflow from diversification filtering.
class SourceOverflow {
  final String sourceId;
  final int hiddenCount;

  SourceOverflow({
    required this.sourceId,
    required this.hiddenCount,
  });

  factory SourceOverflow.fromJson(Map<String, dynamic> json) {
    return SourceOverflow(
      sourceId: (json['source_id'] as String?) ?? '',
      hiddenCount: (json['hidden_count'] as int?) ?? 0,
    );
  }
}

class FeedResponse {
  final List<Content> items;
  final Pagination pagination;
  final List<FeedCluster> clusters;
  final List<SourceOverflow> sourceOverflow;
  final List<TopicOverflow> topicOverflow;

  FeedResponse({
    required this.items,
    required this.pagination,
    this.clusters = const [],
    this.sourceOverflow = const [],
    this.topicOverflow = const [],
  });

  factory FeedResponse.fromJson(Map<String, dynamic> json) {
    return FeedResponse(
      items: (json['items'] as List<dynamic>?)
              ?.map((e) => Content.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      pagination: json['pagination'] != null
          ? Pagination.fromJson(json['pagination'] as Map<String, dynamic>)
          : Pagination(page: 1, perPage: 20, total: 0, hasNext: false),
      clusters: (json['clusters'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map((e) => FeedCluster.fromJson(e))
              .toList() ??
          const [],
      sourceOverflow: (json['source_overflow'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map((e) => SourceOverflow.fromJson(e))
              .toList() ??
          const [],
      topicOverflow: (json['topic_overflow'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map((e) => TopicOverflow.fromJson(e))
              .toList() ??
          const [],
    );
  }
}
