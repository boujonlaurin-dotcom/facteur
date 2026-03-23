import 'package:flutter/material.dart';
import '../../../config/theme.dart';

/// Overlay badge for editorial article types (actu, pas_de_recul, pepite, coup_de_coeur).
///
/// Displays an emoji + label chip with mode-specific colors.
/// Designed to be positioned as an overlay on top of article images.
class EditorialBadge extends StatelessWidget {
  final String badge;
  final bool isSerene;

  const EditorialBadge({
    super.key,
    required this.badge,
    this.isSerene = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final config = _badgeConfig(badge, isDark, colors);
    if (config == null) return const SizedBox.shrink();

    final showEmoji =
        !isSerene || badge == 'pepite' || badge == 'coup_de_coeur';
    final label = showEmoji ? '${config.emoji} ${config.label}' : config.label;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: config.backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: config.textColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  static _BadgeConfig? _badgeConfig(
      String badge, bool isDark, FacteurColors colors) {
    final bgColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.08);
    final txtColor = colors.textSecondary;

    switch (badge) {
      case 'actu':
        return _BadgeConfig(
          emoji: '🔴',
          label: "L'actu du jour",
          backgroundColor: bgColor,
          textColor: txtColor,
        );
      case 'pas_de_recul':
        return _BadgeConfig(
          emoji: '🔭',
          label: 'Le pas de recul',
          backgroundColor: bgColor,
          textColor: txtColor,
        );
      case 'pepite':
        return _BadgeConfig(
          emoji: '🍀',
          label: 'Pépite du jour',
          backgroundColor: bgColor,
          textColor: txtColor,
        );
      case 'coup_de_coeur':
        return _BadgeConfig(
          emoji: '💚',
          label: 'Coup de cœur',
          backgroundColor: bgColor,
          textColor: txtColor,
        );
      default:
        return null;
    }
  }
}

class _BadgeConfig {
  final String emoji;
  final String label;
  final Color backgroundColor;
  final Color textColor;

  const _BadgeConfig({
    required this.emoji,
    required this.label,
    required this.backgroundColor,
    required this.textColor,
  });
}
