import 'package:flutter/material.dart';
import '../../../config/theme.dart';

/// Compact badge showing how many sources cover a topic.
class SourceCoverageBadge extends StatelessWidget {
  final int perspectiveCount;
  final bool isTrending;

  const SourceCoverageBadge({
    super.key,
    required this.perspectiveCount,
    this.isTrending = false,
  });

  @override
  Widget build(BuildContext context) {
    if (perspectiveCount == 0) return const SizedBox.shrink();

    final colors = context.facteurColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.textSecondary.withOpacity(isDark ? 0.15 : 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Couvert par $perspectiveCount ${perspectiveCount == 1 ? 'source' : 'sources'}',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (isTrending) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.trending_up,
              size: 14,
              color: colors.textSecondary,
            ),
          ],
        ],
      ),
    );
  }
}
