import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Les 3 modes de personnalisation du digest quotidien.
///
/// Chaque mode a sa propre identité visuelle (couleur, icône, gradient)
/// et modifie le comportement de l'algorithme de sélection.
///
/// Couleurs définies pour dark ET light mode.
enum DigestMode {
  pourVous(
    key: 'pour_vous',
    label: 'Pour vous',
    subtitle: 'Votre sélection personnalisée',
    emoji: '☀️',
    // Tons chauds ambrés/dorés — "coucher de soleil éditorial"
    color: Color(0xFFD4944C),
    glowColor: Color(0xFFD4944C),
    // Dark mode
    gradientStart: Color(0xFF261C0E),
    gradientEnd: Color(0xFF1A1408),
    backgroundColor: Color(0xFF1A150C),
    cardGlowColor: Color(0x30D4944C),
    // Light mode
    lightGradientStart: Color(0xFFF5E6D0),
    lightGradientEnd: Color(0xFFEDD8BE),
    lightBackgroundColor: Color(0xFFF0DDCA),
  ),
  serein(
    key: 'serein',
    label: 'Serein',
    subtitle: 'Sans politique ni infos anxiogènes',
    emoji: '🌿',
    // Tons verts profonds, forêt — "nature apaisante"
    color: Color(0xFF4CAF7D),
    glowColor: Color(0xFF4CAF7D),
    // Dark mode
    gradientStart: Color(0xFF0E2218),
    gradientEnd: Color(0xFF0A1A10),
    backgroundColor: Color(0xFF0C1A10),
    cardGlowColor: Color(0x304CAF7D),
    // Light mode
    lightGradientStart: Color(0xFFD6EDE0),
    lightGradientEnd: Color(0xFFC5E3D2),
    lightBackgroundColor: Color(0xFFD0E8D8),
  ),
  perspective(
    key: 'perspective',
    label: 'Changer de bord',
    subtitle: "Découvrir l'autre bord politique",
    emoji: '🧭',
    // Tons bleu nuit/indigo — "horizon, ouverture"
    color: Color(0xFF6B8FBF),
    glowColor: Color(0xFF6B8FBF),
    // Dark mode
    gradientStart: Color(0xFF0E1526),
    gradientEnd: Color(0xFF0A101E),
    backgroundColor: Color(0xFF0C1220),
    cardGlowColor: Color(0x306B8FBF),
    // Light mode
    lightGradientStart: Color(0xFFD6E2F0),
    lightGradientEnd: Color(0xFFC5D5E8),
    lightBackgroundColor: Color(0xFFD0DBEB),
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
    required this.glowColor,
    required this.cardGlowColor,
    required this.lightGradientStart,
    required this.lightGradientEnd,
    required this.lightBackgroundColor,
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

  /// Couleur de glow/halo autour de la carte et du sélecteur
  final Color glowColor;

  /// Couleur de glow sur les bords de la carte (dark mode)
  final Color cardGlowColor;

  /// Couleurs du gradient du container digest (dark mode)
  final Color gradientStart;
  final Color gradientEnd;

  /// Couleur de fond de l'écran digest pour ce mode (dark mode)
  final Color backgroundColor;

  /// Couleurs du gradient du container digest (light mode)
  final Color lightGradientStart;
  final Color lightGradientEnd;

  /// Couleur de fond de l'écran digest pour ce mode (light mode)
  final Color lightBackgroundColor;

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
        return PhosphorIcons.compass(PhosphorIconsStyle.fill);
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
