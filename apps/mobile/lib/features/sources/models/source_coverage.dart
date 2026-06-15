/// Couverture par thèmes d'une source — renvoyée par
/// `GET /sources/{source_id}/coverage?days=30`.
///
/// Le backend agrège `contents.theme` sur une fenêtre temporelle, regroupe la
/// longue traîne sous la clé `autres`, et calcule un pourcentage par thème.
/// Le mapping label/couleur reste **côté front** (kit Flux continu
/// `theme_color_mapping.dart`) : `theme` est une clé brute backend.
class CoverageRow {
  /// Clé de thème brute (slug backend), ex. `politics`, `economy`, `autres`.
  final String theme;
  final int count;
  final int pct;

  const CoverageRow({
    required this.theme,
    required this.count,
    required this.pct,
  });

  factory CoverageRow.fromJson(Map<String, dynamic> json) {
    return CoverageRow(
      theme: (json['theme'] as String?) ?? 'autres',
      count: (json['count'] as num?)?.toInt() ?? 0,
      pct: (json['pct'] as num?)?.toInt() ?? 0,
    );
  }
}

class SourceCoverage {
  /// Libellé de période prêt à afficher, ex. « 30 derniers jours ».
  final String periodLabel;
  final int totalCount;

  /// Caption FR déjà formatée côté backend (espaces insécables milliers), ex.
  /// « 3 012 articles publiés sur la période ». `null` ⇒ pas de caption.
  final String? caption;

  /// Lignes triées par pct décroissant (top N + `autres`).
  final List<CoverageRow> rows;

  const SourceCoverage({
    required this.periodLabel,
    required this.totalCount,
    this.caption,
    this.rows = const [],
  });

  bool get isEmpty => rows.isEmpty;

  factory SourceCoverage.fromJson(Map<String, dynamic> json) {
    var rows = const <CoverageRow>[];
    final rawRows = json['rows'];
    if (rawRows is List) {
      try {
        rows = rawRows
            .map((e) => CoverageRow.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        rows = const [];
      }
    }
    return SourceCoverage(
      periodLabel: (json['period_label'] as String?) ?? '',
      totalCount: (json['total_count'] as num?)?.toInt() ?? 0,
      caption: (json['caption'] as String?)?.trim().isEmpty ?? true
          ? null
          : (json['caption'] as String?)?.trim(),
      rows: rows,
    );
  }
}
