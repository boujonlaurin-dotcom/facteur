import 'package:flutter/material.dart';

import '../../../config/theme.dart';

/// Section header for the sources recommendation screen.
///
/// Displays an emoji + title with a subtitle description and a divider.
class RecommendationSectionHeader extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;

  const RecommendationSectionHeader({
    super.key,
    required this.emoji,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return Padding(
      padding: const EdgeInsets.only(
        top: FacteurSpacing.space6,
        bottom: FacteurSpacing.space3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Divider(
                  color: colors.border,
                  height: 1,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: FacteurSpacing.space3,
                ),
                child: Text(
                  '$emoji $title',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              Expanded(
                child: Divider(
                  color: colors.border,
                  height: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: FacteurSpacing.space2),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textTertiary,
                  fontStyle: FontStyle.italic,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
