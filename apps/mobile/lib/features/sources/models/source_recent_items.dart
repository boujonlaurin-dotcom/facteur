import 'smart_search_result.dart';

/// Derniers contenus d'une source, renvoyés par POST /sources/recent-items.
/// Alimente l'animation de conclusion de l'onboarding.
class SourceRecentItems {
  final String sourceId;
  final String name;
  final String? logoUrl;
  final List<SmartSearchRecentItem> items;

  const SourceRecentItems({
    required this.sourceId,
    required this.name,
    this.logoUrl,
    this.items = const [],
  });

  factory SourceRecentItems.fromJson(Map<String, dynamic> json) {
    var items = const <SmartSearchRecentItem>[];
    final rawItems = json['items'];
    if (rawItems is List) {
      try {
        items = rawItems
            .map(
              (i) => SmartSearchRecentItem.fromJson(i as Map<String, dynamic>),
            )
            .toList();
      } catch (_) {
        items = const [];
      }
    }
    return SourceRecentItems(
      sourceId: (json['source_id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      logoUrl: json['logo_url'] as String?,
      items: items,
    );
  }
}
