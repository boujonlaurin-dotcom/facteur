import 'package:flutter/material.dart';

/// Visual mapping for the 9 broad Facteur themes (cf.
/// `packages/api/app/services/ml/topic_theme_mapper.py` — VALID_THEMES).
///
/// Used by sections #3 and #4 of the Flux Continu V1.8 to derive a colored
/// accent and a human-readable French label from a theme slug returned by
/// `GET /api/users/top-themes`.
///
/// Palette rules :
///  - Aucune collision avec les accents éditoriaux (orange Essentiel, vert
///    Bonnes Nouvelles, ardoise Veille).
///  - Distribution harmonieuse sur la roue des teintes (aucun doublon de
///    famille chromatique).
class ThemeVisual {
  final Color accent;
  final String label;

  const ThemeVisual({required this.accent, required this.label});
}

const Map<String, ThemeVisual> themeMap = {
  'tech': ThemeVisual(accent: Color(0xFF1565C0), label: 'Technologie'),
  'environment': ThemeVisual(accent: Color(0xFF00695C), label: 'Environnement'),
  'science': ThemeVisual(accent: Color(0xFF0097A7), label: 'Science'),
  'society': ThemeVisual(accent: Color(0xFF6A1B9A), label: 'Société'),
  'culture': ThemeVisual(accent: Color(0xFFAD1457), label: 'Culture'),
  'economy': ThemeVisual(accent: Color(0xFFF57F17), label: 'Économie'),
  'politics': ThemeVisual(accent: Color(0xFFB71C1C), label: 'Politique'),
  'international': ThemeVisual(accent: Color(0xFF0288D1), label: 'International'),
  'sport': ThemeVisual(accent: Color(0xFFE64A19), label: 'Sport'),
};

/// Fallback theme slugs when `/api/users/top-themes` returns fewer than 2
/// entries (new users, sparse activity). Per PM decision 2026-05-13.
const String fallbackTheme1 = 'tech';
const String fallbackTheme2 = 'environment';

ThemeVisual visualFor(String slug) =>
    themeMap[slug] ??
    const ThemeVisual(accent: Color(0xFF5D5B5A), label: 'Veille');

/// Accent pour les sections sources quand aucune couleur de logo n'est
/// disponible. Bleu-gris neutre intentionnellement distinct de tous les thèmes.
const Color sourceAccentFallback = Color(0xFF607D8B);

/// Couleurs dominantes extraites des logos des sources connues.
/// À enrichir au fur et à mesure (slugs = IDs sources en base).
const Map<String, Color> _sourceAccentMap = {
  // Exemple : 'le-monde': Color(0xFF00508C),
};

/// Retourne la couleur accent d'une source : couleur logo si disponible,
/// sinon [sourceAccentFallback].
Color sourceAccentFor(String sourceSlug) =>
    _sourceAccentMap[sourceSlug] ?? sourceAccentFallback;
