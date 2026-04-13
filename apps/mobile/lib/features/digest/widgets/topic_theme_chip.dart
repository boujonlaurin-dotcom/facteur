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
    final rawLabel = topicSlugToLabel[themeSlug] ??
        themeSlug!.replaceAll('-', ' ').replaceAll('_', ' ');
    final label = rawLabel.isNotEmpty
        ? rawLabel[0].toUpperCase() + rawLabel.substring(1)
        : rawLabel;

    return Text(
      label,
      style: TextStyle(
        color: colors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
