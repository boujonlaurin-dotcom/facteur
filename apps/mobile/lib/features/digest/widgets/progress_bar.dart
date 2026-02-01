import 'package:flutter/material.dart';
import '../../../config/theme.dart';

/// Progress bar showing X/5 completion for digest
class ProgressBar extends StatelessWidget {
  final int processedCount;
  final int totalCount;

  const ProgressBar({
    super.key,
    required this.processedCount,
    this.totalCount = 5,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space4),
      child: Row(
        children: [
          // Progress segments
          Expanded(
            child: Row(
              children: List.generate(totalCount, (index) {
                final isFilled = index < processedCount;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: index < totalCount - 1 ? FacteurSpacing.space2 : 0,
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
          // Count text
          Text(
            '$processedCount/$totalCount',
            style: textTheme.labelMedium?.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
