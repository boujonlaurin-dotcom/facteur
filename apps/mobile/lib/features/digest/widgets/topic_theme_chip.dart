import 'package:flutter/material.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/config/topic_labels.dart';

class TopicThemeChip extends StatelessWidget {
  final String? themeSlug;

  const TopicThemeChip({super.key, required this.themeSlug});

  @override
  Widget build(BuildContext context) {
    if (themeSlug == null) return const SizedBox.shrink();

    final colors = context.facteurColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = colors.textSecondary;
    final rawLabel = topicSlugToLabel[themeSlug] ??
        themeSlug!.replaceAll('-', ' ').replaceAll('_', ' ');
    final label = rawLabel.isNotEmpty
        ? rawLabel[0].toUpperCase() + rawLabel.substring(1)
        : rawLabel;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.15 : 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
