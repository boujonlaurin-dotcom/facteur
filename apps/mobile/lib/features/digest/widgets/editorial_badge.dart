import 'package:flutter/material.dart';
import '../../../config/theme.dart';

/// Resolves editorial badge codes to display labels and colored chips.
///
/// Badge codes: actu, pas_de_recul, pepite, coup_de_coeur.
class EditorialBadge {
  EditorialBadge._();

  /// Returns the display label for a badge code, or null if unknown.
  static String? labelFor(String? badge) {
    switch (badge) {
      case 'actu':
        return "\u{1F534} L'actu du jour";
      case 'pas_de_recul':
        return '\u{1F52D} Le pas de recul';
      case 'pepite':
        return '\u{1F340} P\u00e9pite du jour';
      case 'coup_de_coeur':
        return '\u{1F49A} Coup de c\u{0153}ur';
      default:
        return null;
    }
  }

  /// Returns a colored chip widget for the badge, or null if unknown.
  static Widget? chip(String? badge, {required BuildContext context}) {
    if (badge == null) return null;
    final config = _chipConfig(badge, context);
    if (config == null) return null;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: config.color.withValues(alpha: isDark ? 0.15 : 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        config.label,
        style: TextStyle(
          color: config.color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  static _ChipConfig? _chipConfig(String badge, BuildContext context) {
    final colors = context.facteurColors;
    switch (badge) {
      case 'actu':
        return _ChipConfig(
          label: "\u{1F534} L'actu du jour",
          color: colors.primary,
        );
      case 'pas_de_recul':
        return _ChipConfig(
          label: '\u{1F52D} Le pas de recul',
          color: colors.info,
        );
      case 'pepite':
        return _ChipConfig(
          label: '\u{1F340} P\u00e9pite du jour',
          color: colors.success,
        );
      case 'coup_de_coeur':
        return _ChipConfig(
          label: '\u{1F49A} Coup de c\u{0153}ur',
          color: colors.success,
        );
      default:
        return null;
    }
  }
}

class _ChipConfig {
  final String label;
  final Color color;

  const _ChipConfig({required this.label, required this.color});
}
