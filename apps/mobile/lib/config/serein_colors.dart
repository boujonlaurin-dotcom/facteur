import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Visual identity for the two serein toggle states.
///
/// Extracted from the former DigestMode enum. Each preset has
/// dark-mode and light-mode gradient/background/glow values.
class SereinColors {
  SereinColors._();

  // ── Normal (Tout voir) ────────────────────────────────────────────
  static const normalColor = Color(0xFFD4944C);
  static const normalGlowColor = Color(0xFFD4944C);
  static const normalCardGlowColor = Color(0x30D4944C);
  // Dark
  static const normalGradientStart = Color(0xFF261C0E);
  static const normalGradientEnd = Color(0xFF1A1408);
  static const normalBackgroundColor = Color(0xFF1A150C);
  // Light
  static const normalLightGradientStart = Color(0xFFD9A86A);
  static const normalLightGradientEnd = Color(0xFFC49050);
  static const normalLightBackgroundColor = Color(0xFFE0B87A);

  static IconData get normalIcon =>
      PhosphorIcons.sunDim(PhosphorIconsStyle.fill);

  // ── Serein ────────────────────────────────────────────────────────
  static const sereinColor = Color(0xFF4CAF7D);
  static const sereinGlowColor = Color(0xFF4CAF7D);
  static const sereinCardGlowColor = Color(0x304CAF7D);
  // Dark
  static const sereinGradientStart = Color(0xFF0E2218);
  static const sereinGradientEnd = Color(0xFF0A1A10);
  static const sereinBackgroundColor = Color(0xFF0C1A10);
  // Light
  static const sereinLightGradientStart = Color(0xFF8CC9A5);
  static const sereinLightGradientEnd = Color(0xFF72BD90);
  static const sereinLightBackgroundColor = Color(0xFF7ABF98);

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
