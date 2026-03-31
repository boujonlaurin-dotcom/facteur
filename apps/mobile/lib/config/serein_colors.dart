import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Visual identity for the two serein toggle states.
///
/// Extracted from the former DigestMode enum. Each preset has
/// dark-mode and light-mode gradient/background/glow values.
class SereinColors {
  SereinColors._();

  // ── Normal (Tout voir) — Palette "Terre & Sauge" ─────────────────
  static const normalColor = Color(0xFFC4A882);
  static const normalGlowColor = Color(0xFFC4A882);
  static const normalCardGlowColor = Color(0x30C4A882);
  // Dark
  static const normalGradientStart = Color(0xFF1E1812);
  static const normalGradientEnd = Color(0xFF161109);
  static const normalBackgroundColor = Color(0xFF161109);
  // Light
  static const normalLightGradientStart = Color(0xFFD4BFA5);
  static const normalLightGradientEnd = Color(0xFFC2AC8E);
  static const normalLightBackgroundColor = Color(0xFFD4BFA5);

  static IconData get normalIcon =>
      PhosphorIcons.sunDim(PhosphorIconsStyle.fill);

  // ── Serein — Palette "Terre & Sauge" (vert sauge affirmé) ────────
  static const sereinColor = Color(0xFF5A9478);
  static const sereinGlowColor = Color(0xFF5A9478);
  static const sereinCardGlowColor = Color(0x305A9478);
  // Dark
  static const sereinGradientStart = Color(0xFF0D1F18);
  static const sereinGradientEnd = Color(0xFF091710);
  static const sereinBackgroundColor = Color(0xFF091710);
  // Light
  static const sereinLightGradientStart = Color(0xFF85B8A0);
  static const sereinLightGradientEnd = Color(0xFF6DAA8E);
  static const sereinLightBackgroundColor = Color(0xFF85B8A0);

  static IconData get sereinIcon =>
      PhosphorIcons.flowerLotus(PhosphorIconsStyle.fill);

  // ── Helpers ───────────────────────────────────────────────────────

  static Color accentColor(bool isSerein) =>
      isSerein ? sereinColor : normalColor;

  static Color gradientStart(bool isSerein, {required bool isDark}) => isDark
      ? (isSerein ? sereinGradientStart : normalGradientStart)
      : (isSerein ? sereinLightGradientStart : normalLightGradientStart);

  static Color gradientEnd(bool isSerein, {required bool isDark}) => isDark
      ? (isSerein ? sereinGradientEnd : normalGradientEnd)
      : (isSerein ? sereinLightGradientEnd : normalLightGradientEnd);

  static IconData icon(bool isSerein) =>
      isSerein ? sereinIcon : normalIcon;
}
