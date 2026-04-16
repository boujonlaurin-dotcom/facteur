import 'package:flutter/material.dart';
import '../../../config/theme.dart';
import '../../feed/models/content_model.dart';

/// Resolves editorial badge codes to display labels and colored chips.
///
/// Badge codes: actu, pas_de_recul, pepite, coup_de_coeur,
/// plus carousel-specific: actu_chaude, focus_topic, autre_angle,
/// new_source, new_topic, saved_article, saved_video, saved_audio.
class EditorialBadge {
  EditorialBadge._();

  /// Returns the display label for a badge code, or null if unknown.
  static String? labelFor(String? badge) {
    switch (badge) {
      case 'pas_de_recul':
        return '\u{1F52D} Prendre du recul';
      case 'pepite':
        return '\u{1F340} P\u00e9pite du jour';
      case 'coup_de_coeur':
        return '\u{1F49A} Coup de c\u{0153}ur';
      case 'actu_chaude':
        return '\u{1F534} Actu chaude';
      case 'focus_topic':
        return '\u{1F3AF} Focus';
      case 'autre_angle':
        return '\u{1F50D} Autre angle';
      case 'new_source':
        return '\u{1F195} Nouvelle source';
      case 'new_topic':
        return '\u{1F195} Nouveau sujet';
      case 'saved_article':
        return '\u{1F4CC} Article sauvegard\u00e9';
      case 'saved_video':
        return '\u{1F4CC} Vid\u00e9o sauvegard\u00e9e';
      case 'saved_audio':
        return '\u{1F4CC} Audio sauvegard\u00e9';
      case 'actu_decalee':
        return '\u{1F604} L\'actu d\u00e9cal\u00e9e';
      case 'satire':
        return '\u{1F60F} Satire';
      case 'decale':
        return '\u{1F604} D\u00e9cal\u00e9';
      default:
        return null;
    }
  }

  /// Returns a colored chip widget for the badge, or null if unknown.
  static Widget? chip(String? badge, {required BuildContext context}) {
    if (badge == null) return null;
    final config = _chipConfig(badge, context);
    if (config == null) return null;

    return _buildChip(config, context);
  }

  /// Returns a chip for a carousel badge (uses badge's own label/emoji).
  static Widget carouselChip(
    CarouselItemBadge badge, {
    required BuildContext context,
  }) {
    final color = _colorForCode(badge.code, context);
    final config = _ChipConfig(
      label: '${badge.emoji} ${badge.label}',
      color: color,
    );
    return _buildChip(config, context);
  }

  static Widget _buildChip(_ChipConfig config, BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: config.color.withOpacity(isDark ? 0.15 : 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        config.label,
        style: TextStyle(
          color: config.color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  static Color _colorForCode(String code, BuildContext context) {
    final colors = context.facteurColors;
    switch (code) {
      case 'actu':
      case 'actu_chaude':
      case 'focus_topic':
        return colors.primary;
      case 'pas_de_recul':
      case 'autre_angle':
      case 'new_source':
      case 'new_topic':
        return colors.info;
      case 'pepite':
      case 'coup_de_coeur':
        return colors.success;
      case 'saved_article':
      case 'saved_video':
      case 'saved_audio':
        return colors.warning;
      case 'actu_decalee':
      case 'satire':
      case 'decale':
        return Colors.orange;
      default:
        return colors.textSecondary;
    }
  }

  static _ChipConfig? _chipConfig(String badge, BuildContext context) {
    final colors = context.facteurColors;
    switch (badge) {
      case 'pas_de_recul':
        return _ChipConfig(
          label: '\u{1F52D} Prendre du recul',
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
      case 'actu_chaude':
        return _ChipConfig(
          label: '\u{1F534} Actu chaude',
          color: colors.primary,
        );
      case 'focus_topic':
        return _ChipConfig(
          label: '\u{1F3AF} Focus',
          color: colors.primary,
        );
      case 'autre_angle':
        return _ChipConfig(
          label: '\u{1F50D} Autre angle',
          color: colors.info,
        );
      case 'new_source':
        return _ChipConfig(
          label: '\u{1F195} Nouvelle source',
          color: colors.info,
        );
      case 'new_topic':
        return _ChipConfig(
          label: '\u{1F195} Nouveau sujet',
          color: colors.info,
        );
      case 'saved_article':
        return _ChipConfig(
          label: '\u{1F4CC} Article sauvegard\u00e9',
          color: colors.warning,
        );
      case 'saved_video':
        return _ChipConfig(
          label: '\u{1F4CC} Vid\u00e9o sauvegard\u00e9e',
          color: colors.warning,
        );
      case 'saved_audio':
        return _ChipConfig(
          label: '\u{1F4CC} Audio sauvegard\u00e9',
          color: colors.warning,
        );
      case 'actu_decalee':
        return _ChipConfig(
          label: '\u{1F604} L\'actu d\u00e9cal\u00e9e',
          color: Colors.orange,
        );
      case 'satire':
        return _ChipConfig(
          label: '\u{1F60F} Satire',
          color: Colors.orange,
        );
      case 'decale':
        return _ChipConfig(
          label: '\u{1F604} D\u00e9cal\u00e9',
          color: Colors.orange,
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
