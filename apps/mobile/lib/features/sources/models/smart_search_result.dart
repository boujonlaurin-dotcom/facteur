/// Model for smart search API response items.
///
/// Maps to backend schema `SmartSearchResultItem` from
/// `POST /api/sources/smart-search`.

class SmartSearchRecentItem {
  final String title;
  final String publishedAt;

  const SmartSearchRecentItem({
    required this.title,
    this.publishedAt = '',
  });

  factory SmartSearchRecentItem.fromJson(Map<String, dynamic> json) {
    return SmartSearchRecentItem(
      title: (json['title'] as String?) ?? '',
      publishedAt: (json['published_at'] as String?) ?? '',
    );
  }
}

class SmartSearchResult {
  final String name;
  final String type;
  final String url;
  final String feedUrl;
  final String? faviconUrl;
  final String? description;
  final bool inCatalog;
  final bool isCurated;
  final String? sourceId;
  final List<SmartSearchRecentItem> recentItems;
  final double score;
  final String sourceLayer;

  const SmartSearchResult({
    required this.name,
    required this.type,
    required this.url,
    required this.feedUrl,
    this.faviconUrl,
    this.description,
    this.inCatalog = false,
    this.isCurated = false,
    this.sourceId,
    this.recentItems = const [],
    this.score = 0.0,
    this.sourceLayer = 'unknown',
  });

  factory SmartSearchResult.fromJson(Map<String, dynamic> json) {
    List<SmartSearchRecentItem> items = const [];
    try {
      final rawItems = json['recent_items'];
      if (rawItems is List) {
        items = rawItems
            .map((e) =>
                SmartSearchRecentItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {
      // Defensive: keep empty list on malformed data
    }

    return SmartSearchResult(
      name: (json['name'] as String?) ?? 'Source inconnue',
      type: (json['type'] as String?) ?? 'article',
      url: (json['url'] as String?) ?? '',
      feedUrl: (json['feed_url'] as String?) ?? '',
      faviconUrl: json['favicon_url'] as String?,
      description: json['description'] as String?,
      inCatalog: (json['in_catalog'] as bool?) ?? false,
      isCurated: (json['is_curated'] as bool?) ?? false,
      sourceId: json['source_id']?.toString(),
      recentItems: items,
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      sourceLayer: (json['source_layer'] as String?) ?? 'unknown',
    );
  }
}

class SmartSearchResponse {
  final String queryNormalized;
  final List<SmartSearchResult> results;
  final bool cacheHit;
  final List<String> layersCalled;
  final int latencyMs;

  const SmartSearchResponse({
    required this.queryNormalized,
    required this.results,
    this.cacheHit = false,
    this.layersCalled = const [],
    this.latencyMs = 0,
  });

  factory SmartSearchResponse.fromJson(Map<String, dynamic> json) {
    List<SmartSearchResult> results = const [];
    try {
      final rawResults = json['results'];
      if (rawResults is List) {
        results = rawResults
            .map(
                (e) => SmartSearchResult.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {
      // Defensive: keep empty list
    }

    List<String> layers = const [];
    try {
      final rawLayers = json['layers_called'];
      if (rawLayers is List) {
        layers = rawLayers.cast<String>();
      }
    } catch (_) {}

    return SmartSearchResponse(
      queryNormalized: (json['query_normalized'] as String?) ?? '',
      results: results,
      cacheHit: (json['cache_hit'] as bool?) ?? false,
      layersCalled: layers,
      latencyMs: (json['latency_ms'] as int?) ?? 0,
    );
  }
}
