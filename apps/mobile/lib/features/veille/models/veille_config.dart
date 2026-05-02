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
