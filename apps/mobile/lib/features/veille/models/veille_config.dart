import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../sources/models/source_model.dart';

@immutable
class VeilleTheme {
  final String id;
  final String label;
  final String meta;
  final String iconKey;
  final String? emoji;
  final bool hot;
  const VeilleTheme({
    required this.id,
    required this.label,
    required this.meta,
    required this.iconKey,
    this.emoji,
    this.hot = false,
  });
}

@immutable
class VeilleTopic {
  final String id;
  final String label;
  final String reason;
  const VeilleTopic({
    required this.id,
    required this.label,
    required this.reason,
  });
}

@immutable
class VeilleSource {
  final String id;
  final String letter;
  final String name;
  final String? meta;
  final String? why;
  final String? logoUrl;
  final String biasStance;
  final SourceType type;
  final String? editorialMeta;
  const VeilleSource({
    required this.id,
    required this.letter,
    required this.name,
    this.meta,
    this.why,
    this.logoUrl,
    this.biasStance = 'unknown',
    this.type = SourceType.article,
    this.editorialMeta,
  });

  /// Construit un [Source] (modèle catalogue) à partir des champs mock —
  /// permet de réutiliser `SourceLogoAvatar` et `SourceDetailModal` du
  /// feature `sources/` sans aller chercher en base.
  Source toCatalogSource() {
    return Source(
      id: id,
      name: name,
      type: type,
      logoUrl: logoUrl,
      biasStance: biasStance,
      description: editorialMeta ?? meta,
    );
  }
}

@immutable
class VeillePresetSource {
  final String id;
  final String name;
  final String url;
  final String? logoUrl;

  const VeillePresetSource({
    required this.id,
    required this.name,
    required this.url,
    this.logoUrl,
  });

  factory VeillePresetSource.fromJson(Map<String, dynamic> json) {
    return VeillePresetSource(
      id: json['id'] as String,
      name: json['name'] as String,
      url: json['url'] as String,
      logoUrl: json['logo_url'] as String?,
    );
  }
}

@immutable
class VeillePreset {
  final String slug;
  final String label;
  final String accroche;
  final String themeId;
  final String themeLabel;
  final List<String> topics;
  final List<String> purposes;
  final String editorialBrief;
  final List<VeillePresetSource> sources;

  const VeillePreset({
    required this.slug,
    required this.label,
    required this.accroche,
    required this.themeId,
    required this.themeLabel,
    required this.topics,
    required this.purposes,
    required this.editorialBrief,
    required this.sources,
  });

  factory VeillePreset.fromJson(Map<String, dynamic> json) {
    return VeillePreset(
      slug: json['slug'] as String,
      label: json['label'] as String,
      accroche: json['accroche'] as String,
      themeId: json['theme_id'] as String,
      themeLabel: json['theme_label'] as String,
      topics: ((json['topics'] as List?) ?? const [])
          .whereType<String>()
          .toList(),
      purposes: ((json['purposes'] as List?) ?? const [])
          .whereType<String>()
          .toList(),
      editorialBrief: (json['editorial_brief'] as String?) ?? '',
      sources: ((json['sources'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(VeillePresetSource.fromJson)
          .toList(),
    );
  }
}

enum VeilleFrequency {
  weekly('weekly', 'Chaque semaine', recommended: true),
  biweekly('biweek', 'Tous les 15 jours'),
  monthly('month', 'Chaque mois');

  final String id;
  final String label;
  final bool recommended;
  const VeilleFrequency(this.id, this.label, {this.recommended = false});
}

enum VeilleDay {
  mon('mon', 'Lun'),
  tue('tue', 'Mar'),
  wed('wed', 'Mer'),
  thu('thu', 'Jeu'),
  fri('fri', 'Ven'),
  sat('sat', 'Sam'),
  sun('sun', 'Dim');

  final String id;
  final String label;
  const VeilleDay(this.id, this.label);
}

/// Résolution Phosphor pour les icônes de thèmes du flow Veille.
IconData phosphorThemeIcon(String key) {
  switch (key) {
    case 'graduation-cap':
      return PhosphorIcons.graduationCap();
    case 'leaf':
      return PhosphorIcons.leaf();
    case 'newspaper':
      return PhosphorIcons.newspaper();
    case 'lightning':
      return PhosphorIcons.lightning();
    case 'globe-hemisphere-west':
      return PhosphorIcons.globeHemisphereWest();
    case 'first-aid-kit':
      return PhosphorIcons.firstAidKit();
    case 'compass':
      return PhosphorIcons.compass();
    case 'chart-line-up':
      return PhosphorIcons.chartLineUp();
    default:
      return PhosphorIcons.circle();
  }
}
