import 'package:flutter/material.dart';

import '../../../config/theme.dart';

/// Discrete progress dots for editorial_v1 layout (D6).
///
/// Shows N dots, filled when a subject has been covered.
class ProgressDots extends StatelessWidget {
  final int processedCount;
  final int totalCount;

  const ProgressDots({
    super.key,
    required this.processedCount,
    required this.totalCount,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(totalCount, (index) {
        final isFilled = index < processedCount;
        return Padding(
          padding: EdgeInsets.only(left: index > 0 ? 6 : 0),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isFilled ? colors.primary : Colors.transparent,
              border: isFilled
                  ? null
                  : Border.all(
                      color: colors.border.withValues(alpha: 0.4),
                      width: 1,
                    ),
            ),
          ),
        );
      }),
    );
  }
}
