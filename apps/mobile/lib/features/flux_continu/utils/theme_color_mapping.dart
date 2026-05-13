import 'package:flutter/material.dart';

/// Visual mapping for the 9 broad Facteur themes (cf.
/// `packages/api/app/services/ml/topic_theme_mapper.py` — VALID_THEMES).
///
/// Used by sections #3 and #4 of the Flux Continu V1.8 to derive a colored
/// accent and a human-readable French label from a theme slug returned by
/// `GET /api/users/top-themes`.
class ThemeVisual {
  final Color accent;
  final String label;

  const ThemeVisual({required this.accent, required this.label});
}

const Map<String, ThemeVisual> themeMap = {
  'tech': ThemeVisual(accent: Color(0xFF2C3E50), label: 'Technologie'),
  'environment':
      ThemeVisual(accent: Color(0xFF6C3483), label: 'Environnement'),
  'science': ThemeVisual(accent: Color(0xFF2980B9), label: 'Science'),
  'society': ThemeVisual(accent: Color(0xFF8E44AD), label: 'Société'),
  'culture': ThemeVisual(accent: Color(0xFFB36BFF), label: 'Culture'),
  'economy': ThemeVisual(accent: Color(0xFFC2185B), label: 'Économie'),
  'politics': ThemeVisual(accent: Color(0xFFD35400), label: 'Politique'),
  'international':
      ThemeVisual(accent: Color(0xFF1ABC9C), label: 'International'),
  'sport': ThemeVisual(accent: Color(0xFFE67E22), label: 'Sport'),
};

/// Fallback theme slugs when `/api/users/top-themes` returns fewer than 2
/// entries (new users, sparse activity). Per PM decision 2026-05-13.
const String fallbackTheme1 = 'tech';
const String fallbackTheme2 = 'environment';

ThemeVisual visualFor(String slug) =>
    themeMap[slug] ??
    const ThemeVisual(accent: Color(0xFF5D5B5A), label: 'Veille');
