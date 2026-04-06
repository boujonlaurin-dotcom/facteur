import 'package:flutter/material.dart';
import '../../../config/theme.dart';

/// Block displaying a quick analysis of media divergences on a topic.
/// Hidden when [divergenceAnalysis] is null.
class DivergenceAnalysisBlock extends StatelessWidget {
  final String? divergenceAnalysis;
  final String? biasHighlights;
  final VoidCallback? onCompare;

  const DivergenceAnalysisBlock({
    super.key,
    this.divergenceAnalysis,
    this.biasHighlights,
    this.onCompare,
  });

  @override
  Widget build(BuildContext context) {
    if (divergenceAnalysis == null) return const SizedBox.shrink();

    final colors = context.facteurColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.textSecondary.withValues(alpha: isDark ? 0.08 : 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(
            '\u{1F50D} Analyse des angles m\u00e9diatiques',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),

          // Analysis text
          Text(
            divergenceAnalysis!,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.7)
                  : colors.textSecondary,
            ),
          ),

          // Bias highlights
          if (biasHighlights != null) ...[
            const SizedBox(height: 8),
            Text(
              biasHighlights!,
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.5)
                    : colors.textSecondary.withValues(alpha: 0.7),
              ),
            ),
          ],

          // CTA
          if (onCompare != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: onCompare,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Comparer les sources \u2192',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
