import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../config/theme.dart';
import 'markdown_text.dart';
import 'source_coverage_badge.dart';

/// Block displaying a quick analysis of media divergences on a topic.
/// Hidden when [divergenceAnalysis] is null.
class DivergenceAnalysisBlock extends StatelessWidget {
  final String? divergenceAnalysis;
  final String? biasHighlights;
  final VoidCallback? onCompare;
  final int perspectiveCount;

  const DivergenceAnalysisBlock({
    super.key,
    this.divergenceAnalysis,
    this.biasHighlights,
    this.onCompare,
    this.perspectiveCount = 0,
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
            "\u{1F50D} L'analyse Facteur",
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: colors.textSecondary,
            ),
          ),

          // Bias highlights badge
          if (biasHighlights != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: colors.textSecondary.withValues(alpha: isDark ? 0.10 : 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                biasHighlights!,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],

          // Analysis text
          const SizedBox(height: 8),
          MarkdownText(
            text: divergenceAnalysis!,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.7)
                  : colors.textSecondary,
            ),
          ),

          // CTA + source coverage badge row
          if (onCompare != null || perspectiveCount > 1) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (onCompare != null)
                  GestureDetector(
                    onTap: onCompare,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: colors.textSecondary.withValues(alpha: isDark ? 0.12 : 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(PhosphorIcons.arrowSquareOut(), size: 13, color: colors.textSecondary),
                          const SizedBox(width: 5),
                          Text(
                            'Comparer les sources',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (onCompare != null && perspectiveCount > 1)
                  const SizedBox(width: 8),
                if (perspectiveCount > 1)
                  SourceCoverageBadge(
                    perspectiveCount: perspectiveCount,
                    isTrending: false,
                  ),
              ],
            ),
          ],

          // Mistral attribution
          const SizedBox(height: 8),
          Text(
            'Généré via modèle Mistral Medium',
            style: TextStyle(
              fontSize: 10,
              color: colors.textSecondary.withValues(alpha: 0.4),
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}
