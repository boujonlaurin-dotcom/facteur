import '../../feed/models/content_model.dart';
import 'source_model.dart';

/// Part d'un thème dans la couverture d'une source — fiche source v3
/// (`GET /sources/{id}/profile`).
///
/// `theme` reste une clé brute backend (mapping label/couleur côté front, kit
/// Flux continu). `share` ∈ [0, 1] = `count / total` : le mobile en dérive le
/// pourcentage affiché.
class ThemeShare {
  final String theme;
  final int count;
  final double share;

  const ThemeShare({
    required this.theme,
    required this.count,
    required this.share,
  });

  factory ThemeShare.fromJson(Map<String, dynamic> json) {
    return ThemeShare(
      theme: (json['theme'] as String?) ?? 'autres',
      count: (json['count'] as num?)?.toInt() ?? 0,
      share: (json['share'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Profil unifié d'une source pour la fiche v3 — renvoyé par
/// `GET /sources/{id}/profile`.
///
/// Regroupe les signaux produit qui aident à décider de suivre une source :
/// articles récents (objets [Content] complets → carte standard cliquable),
/// couverture par thèmes ([themeDistribution] + [articles30d]) et la date du
/// plus ancien contenu ([oldestContentAt], hors fenêtre) pour calculer la
/// fréquence de publication côté client.
class SourceProfile {
  final List<Content> recentArticles;
  final List<ThemeShare> themeDistribution;
  final int articles30d;
  final DateTime? oldestContentAt;

  /// Source complète renvoyée par `/profile` ([SourceResponse] backend).
  /// Contrairement au `SourceMini` léger qui ouvre la fiche depuis le reader,
  /// elle porte `follower_count`, les scores A-E, `description`, la reco perso
  /// et `premium_connection`. Nullable → rétro-compatible (tests / payloads
  /// anciens sans ce champ). La fiche l'utilise pour enrichir l'affichage dès
  /// que `/profile` répond.
  final Source? source;

  const SourceProfile({
    this.recentArticles = const [],
    this.themeDistribution = const [],
    this.articles30d = 0,
    this.oldestContentAt,
    this.source,
  });

  bool get hasCoverage => themeDistribution.isNotEmpty;
  bool get hasArticles => recentArticles.isNotEmpty;

  factory SourceProfile.fromJson(Map<String, dynamic> json) {
    final rawOldest = json['oldest_content_at'];
    final rawSource = json['source'];
    return SourceProfile(
      recentArticles: _parseList(json['recent_articles'], Content.fromJson),
      themeDistribution:
          _parseList(json['theme_distribution'], ThemeShare.fromJson),
      articles30d: (json['articles_30d'] as num?)?.toInt() ?? 0,
      oldestContentAt: rawOldest is String ? DateTime.tryParse(rawOldest) : null,
      source: rawSource is Map<String, dynamic>
          ? Source.fromJson(rawSource)
          : null,
    );
  }

  /// Parse défensif d'une liste d'objets JSON (ignore les éléments non-Map).
  static List<T> _parseList<T>(
    dynamic raw,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().map(fromJson).toList();
  }
}
