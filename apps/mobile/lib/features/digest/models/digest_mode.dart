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
    emoji: '☀️',
    color: Color(0xFFCB9B6A),
    gradientStart: Color(0xFF1C1814),
    gradientEnd: Color(0xFF262018),
    backgroundColor: Color(0xFF181410),
  ),
  serein(
    key: 'serein',
    label: 'Serein',
    subtitle: 'Sans politique ni infos anxiogènes',
    emoji: '🌿',
    color: Color(0xFF3D8B6E),
    gradientStart: Color(0xFF141C18),
    gradientEnd: Color(0xFF1A2620),
    backgroundColor: Color(0xFF0E1610),
  ),
  perspective(
    key: 'perspective',
    label: 'Changer de bord',
    subtitle: "Découvrir l'autre bord politique",
    emoji: '🧭',
    color: Color(0xFF5A7BA8),
    gradientStart: Color(0xFF14161E),
    gradientEnd: Color(0xFF1A1E2A),
    backgroundColor: Color(0xFF0E1018),
  );

  const DigestMode({
    required this.key,
    required this.label,
    required this.subtitle,
    required this.emoji,
    this.color,
    required this.gradientStart,
    required this.gradientEnd,
    required this.backgroundColor,
  });

  /// Clé API (stockée en user_preferences)
  final String key;

  /// Label court affiché sous les badges
  final String label;

  /// Sous-titre contextuel affiché dans le container digest
  final String subtitle;

  /// Emoji affiché dans le badge de sélection
  final String emoji;

  /// Couleur du mode (null = utilise primary/terracotta)
  final Color? color;

  /// Couleurs du gradient du container digest (dark mode)
  final Color gradientStart;
  final Color gradientEnd;

  /// Couleur de fond de l'écran digest pour ce mode
  final Color backgroundColor;

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
