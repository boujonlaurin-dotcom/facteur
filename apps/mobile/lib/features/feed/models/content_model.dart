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

  ScoreContribution({
    required this.label,
    required this.points,
    this.isPositive = true,
  });

  factory ScoreContribution.fromJson(Map<String, dynamic> json) {
    return ScoreContribution(
      label: (json['label'] as String?) ?? 'Facteur',
      points: (json['points'] as num?)?.toDouble() ?? 0.0,
      isPositive: (json['is_positive'] as bool?) ?? true,
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
  final RecommendationReason? recommendationReason;
  final String? noteText;
  final DateTime? noteUpdatedAt;

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
    this.recommendationReason,
    this.noteText,
    this.noteUpdatedAt,
  });

  bool get hasNote => noteText != null && noteText!.isNotEmpty;

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
      recommendationReason: recommendationReason,
      noteText: null,
      noteUpdatedAt: null,
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
        recommendationReason: (recJson is Map<String, dynamic>)
            ? RecommendationReason.fromJson(recJson)
            : null,
        noteText: json['note_text'] as String?,
        noteUpdatedAt: json['note_updated_at'] != null
            ? DateTime.tryParse(json['note_updated_at'] as String)
            : null,
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
    RecommendationReason? recommendationReason,
    String? noteText,
    DateTime? noteUpdatedAt,
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
      recommendationReason: recommendationReason ?? this.recommendationReason,
      noteText: noteText ?? this.noteText,
      noteUpdatedAt: noteUpdatedAt ?? this.noteUpdatedAt,
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

class FeedResponse {
  final List<Content> items;
  final Pagination pagination;

  FeedResponse({
    required this.items,
    required this.pagination,
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
    );
  }
}
