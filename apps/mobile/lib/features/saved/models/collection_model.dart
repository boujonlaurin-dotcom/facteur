/// Modèle de collection de sauvegardes.
class Collection {
  final String id;
  final String name;
  final int position;
  final int itemCount;
  final int readCount;
  final List<String?> thumbnails;
  final DateTime createdAt;

  Collection({
    required this.id,
    required this.name,
    this.position = 0,
    this.itemCount = 0,
    this.readCount = 0,
    this.thumbnails = const [],
    required this.createdAt,
  });

  factory Collection.fromJson(Map<String, dynamic> json) {
    return Collection(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      position: (json['position'] as int?) ?? 0,
      itemCount: (json['item_count'] as int?) ?? 0,
      readCount: (json['read_count'] as int?) ?? 0,
      thumbnails: (json['thumbnails'] as List<dynamic>?)
              ?.map((e) => e as String?)
              .toList() ??
          const [],
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// Compteur d'articles par thème.
class ThemeCount {
  final String theme;
  final int count;

  ThemeCount({required this.theme, required this.count});

  factory ThemeCount.fromJson(Map<String, dynamic> json) {
    return ThemeCount(
      theme: (json['theme'] as String?) ?? '',
      count: (json['count'] as int?) ?? 0,
    );
  }
}

/// Résumé des sauvegardes pour les nudges.
class SavedSummary {
  final int totalSaved;
  final int unreadCount;
  final int recentCount7d;
  final List<ThemeCount> topThemes;

  SavedSummary({
    this.totalSaved = 0,
    this.unreadCount = 0,
    this.recentCount7d = 0,
    this.topThemes = const [],
  });

  factory SavedSummary.fromJson(Map<String, dynamic> json) {
    return SavedSummary(
      totalSaved: (json['total_saved'] as int?) ?? 0,
      unreadCount: (json['unread_count'] as int?) ?? 0,
      recentCount7d: (json['recent_count_7d'] as int?) ?? 0,
      topThemes: (json['top_themes'] as List<dynamic>?)
              ?.map((e) => ThemeCount.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}
