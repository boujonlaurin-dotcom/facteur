import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Les 3 modes de personnalisation du digest quotidien.
///
/// Chaque mode a sa propre identité visuelle (couleur, icône, gradient)
/// et modifie le comportement de l'algorithme de sélection.
///
/// Note: theme_focus est déprécié pour le moment (Epic 11 v1).
enum DigestMode {
  pourVous(
    key: 'pour_vous',
    label: 'Pour vous',
    subtitle: 'Votre sélection personnalisée',
    gradientStart: Color(0xFF1A1918),
    gradientEnd: Color(0xFF2C2A29),
  ),
  serein(
    key: 'serein',
    label: 'Serein',
    subtitle: 'Sans politique ni infos anxiogènes',
    color: Color(0xFF2ECC71),
    gradientStart: Color(0xFF1A201A),
    gradientEnd: Color(0xFF1E2C1E),
  ),
  perspective(
    key: 'perspective',
    label: 'Changer de bord',
    subtitle: "Découvrir l'autre bord politique",
    color: Color(0xFF6B9AC4),
    gradientStart: Color(0xFF1A1A20),
    gradientEnd: Color(0xFF201A1A),
  );

  const DigestMode({
    required this.key,
    required this.label,
    required this.subtitle,
    this.color,
    required this.gradientStart,
    required this.gradientEnd,
  });

  /// Clé API (stockée en user_preferences)
  final String key;

  /// Label court affiché sous les badges
  final String label;

  /// Sous-titre contextuel affiché dans le container digest
  final String subtitle;

  /// Couleur du mode (null = utilise primary/terracotta)
  final Color? color;

  /// Couleurs du gradient du container digest (dark mode)
  final Color gradientStart;
  final Color gradientEnd;

  /// Retourne la couleur effective (couleur du mode ou primary par défaut)
  Color effectiveColor(Color primaryColor) => color ?? primaryColor;

  /// Retourne l'icône Phosphor pour ce mode
  IconData get icon {
    switch (this) {
      case DigestMode.pourVous:
        return PhosphorIcons.sunDim(PhosphorIconsStyle.fill);
      case DigestMode.serein:
        return PhosphorIcons.leaf(PhosphorIconsStyle.fill);
      case DigestMode.perspective:
        return PhosphorIcons.userSwitch(PhosphorIconsStyle.fill);
    }
  }

  /// Trouve un mode par sa clé API
  static DigestMode fromKey(String key) {
    return DigestMode.values.firstWhere(
      (m) => m.key == key,
      orElse: () => DigestMode.pourVous,
    );
  }
}
