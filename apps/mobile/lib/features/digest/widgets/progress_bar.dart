import 'package:flutter/material.dart';
import '../../../config/theme.dart';

/// Progress bar showing X/N completion for digest with threshold marker.
/// The threshold indicates when completion is triggered (e.g., 5/7).
class ProgressBar extends StatelessWidget {
  final int processedCount;
  final int totalCount;
  final int? completionThreshold;

  const ProgressBar({
    super.key,
    required this.processedCount,
    this.totalCount = 7,
    this.completionThreshold,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final threshold = completionThreshold ?? totalCount;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space4),
      child: Row(
        children: [
          // Progress segments
          Expanded(
            child: Row(
              children: List.generate(totalCount, (index) {
                final isFilled = index < processedCount;
                final isThresholdBoundary =
                    threshold < totalCount && index == threshold - 1;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: index < totalCount - 1
                          ? (isThresholdBoundary
                              ? FacteurSpacing.space3
                              : FacteurSpacing.space2)
                          : 0,
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isFilled
                            ? colors.primary
                            : colors.backgroundSecondary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(width: FacteurSpacing.space3),
          // Count text showing progress toward threshold
          Text(
            '$processedCount/$threshold',
            style: textTheme.labelMedium?.copyWith(
              color: processedCount >= threshold
                  ? colors.primary
                  : colors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
