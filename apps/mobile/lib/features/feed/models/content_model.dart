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

enum HiddenReason {
  source,
  topic,
}

class Content {
  final String id;
  final String title;
  final String url;
  final String? thumbnailUrl;
  final ContentType contentType;
  final int? durationSeconds;
  final DateTime publishedAt;
  final Source source;
  final ContentStatus status;
  final bool isSaved;
  final bool isHidden;

  Content({
    required this.id,
    required this.title,
    required this.url,
    this.thumbnailUrl,
    required this.contentType,
    this.durationSeconds,
    required this.publishedAt,
    required this.source,
    this.status = ContentStatus.unseen,
    this.isSaved = false,
    this.isHidden = false,
  });

  factory Content.fromJson(Map<String, dynamic> json) {
    return Content(
      id: json['id'] as String,
      title: json['title'] as String,
      url: json['url'] as String,
      thumbnailUrl: json['thumbnail_url'] as String?,
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
    );
  }

  Content copyWith({
    String? id,
    String? title,
    String? url,
    String? thumbnailUrl,
    ContentType? contentType,
    int? durationSeconds,
    DateTime? publishedAt,
    Source? source,
    ContentStatus? status,
    bool? isSaved,
    bool? isHidden,
  }) {
    return Content(
      id: id ?? this.id,
      title: title ?? this.title,
      url: url ?? this.url,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      contentType: contentType ?? this.contentType,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      publishedAt: publishedAt ?? this.publishedAt,
      source: source ?? this.source,
      status: status ?? this.status,
      isSaved: isSaved ?? this.isSaved,
      isHidden: isHidden ?? this.isHidden,
    );
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
