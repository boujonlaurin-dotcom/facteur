/// Model for community recommendation carousel items (🌻).
///
/// Separate from Freezed models to avoid requiring code generation
/// for this new feature. Parsed from the `community_carousel` field
/// in the digest API response.
class CommunityCarouselItem {
  final String contentId;
  final String title;
  final String url;
  final String? thumbnailUrl;
  final String? description;
  final String contentType;
  final int? durationSeconds;
  final DateTime? publishedAt;
  final String sourceName;
  final String? sourceLogoUrl;
  final String? sourceId;
  final int sunflowerCount;
  final bool isLiked;
  final bool isSaved;
  final List<String> topics;

  const CommunityCarouselItem({
    required this.contentId,
    required this.title,
    required this.url,
    this.thumbnailUrl,
    this.description,
    this.contentType = 'article',
    this.durationSeconds,
    this.publishedAt,
    this.sourceName = '',
    this.sourceLogoUrl,
    this.sourceId,
    this.sunflowerCount = 0,
    this.isLiked = false,
    this.isSaved = false,
    this.topics = const [],
  });

  factory CommunityCarouselItem.fromJson(Map<String, dynamic> json) {
    final source = json['source'] as Map<String, dynamic>?;
    return CommunityCarouselItem(
      contentId: json['content_id'] as String,
      title: (json['title'] as String?) ?? 'Sans titre',
      url: (json['url'] as String?) ?? '',
      thumbnailUrl: json['thumbnail_url'] as String?,
      description: json['description'] as String?,
      contentType: (json['content_type'] as String?) ?? 'article',
      durationSeconds: json['duration_seconds'] as int?,
      publishedAt: json['published_at'] != null
          ? DateTime.tryParse(json['published_at'] as String)
          : null,
      sourceName: (source?['name'] as String?) ?? '',
      sourceLogoUrl: source?['logo_url'] as String?,
      sourceId: source?['id']?.toString(),
      sunflowerCount: (json['sunflower_count'] as int?) ?? 0,
      isLiked: (json['is_liked'] as bool?) ?? false,
      isSaved: (json['is_saved'] as bool?) ?? false,
      topics: (json['topics'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  CommunityCarouselItem copyWith({
    bool? isLiked,
    bool? isSaved,
  }) {
    return CommunityCarouselItem(
      contentId: contentId,
      title: title,
      url: url,
      thumbnailUrl: thumbnailUrl,
      description: description,
      contentType: contentType,
      durationSeconds: durationSeconds,
      publishedAt: publishedAt,
      sourceName: sourceName,
      sourceLogoUrl: sourceLogoUrl,
      sourceId: sourceId,
      sunflowerCount: sunflowerCount,
      isLiked: isLiked ?? this.isLiked,
      isSaved: isSaved ?? this.isSaved,
      topics: topics,
    );
  }
}
