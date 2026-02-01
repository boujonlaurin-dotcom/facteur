import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';

/// Widget displaying digest completion statistics
/// Shows counts for articles read, saved, and dismissed
class DigestSummary extends StatelessWidget {
  final int articlesRead;
  final int articlesSaved;
  final int articlesDismissed;
  final int? closureTimeSeconds;

  const DigestSummary({
    super.key,
    required this.articlesRead,
    required this.articlesSaved,
    required this.articlesDismissed,
    this.closureTimeSeconds,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(FacteurSpacing.space4),
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(FacteurRadius.small),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Stats row with 3 columns
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatColumn(
                context: context,
                icon: PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
                iconColor: colors.success,
                count: articlesRead,
                label: 'lus',
              ),
              _buildDivider(colors),
              _buildStatColumn(
                context: context,
                icon: PhosphorIcons.bookmark(PhosphorIconsStyle.fill),
                iconColor: colors.primary,
                count: articlesSaved,
                label: 'sauv.',
              ),
              _buildDivider(colors),
              _buildStatColumn(
                context: context,
                icon: PhosphorIcons.eyeSlash(PhosphorIconsStyle.fill),
                iconColor: colors.textSecondary,
                count: articlesDismissed,
                label: 'passés',
              ),
            ],
          ),

          // Optional time display
          if (closureTimeSeconds != null) ...[
            const SizedBox(height: FacteurSpacing.space3),
            _buildTimeDisplay(context, colors, textTheme),
          ],
        ],
      ),
    );
  }

  Widget _buildStatColumn({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required int count,
    required String label,
  }) {
    final textTheme = Theme.of(context).textTheme;

    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: iconColor,
            size: 24,
          ),
          const SizedBox(height: FacteurSpacing.space1),
          Text(
            '$count',
            style: textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 24,
            ),
          ),
          Text(
            label,
            style: textTheme.bodySmall?.copyWith(
              color: iconColor.withValues(alpha: 0.8),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider(FacteurColors colors) {
    return Container(
      width: 1,
      height: 50,
      color: colors.surface.withValues(alpha: 0.5),
    );
  }

  Widget _buildTimeDisplay(
    BuildContext context,
    FacteurColors colors,
    TextTheme textTheme,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FacteurSpacing.space3,
        vertical: FacteurSpacing.space2,
      ),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(FacteurRadius.small / 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            PhosphorIcons.clock(PhosphorIconsStyle.regular),
            size: 14,
            color: colors.textSecondary,
          ),
          const SizedBox(width: FacteurSpacing.space1),
          Text(
            _formatDuration(closureTimeSeconds!),
            style: textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;

    if (minutes > 0 && seconds > 0) {
      return '$minutes min ${seconds}s';
    } else if (minutes > 0) {
      return '$minutes min';
    } else {
      return '$seconds s';
    }
  }
}
