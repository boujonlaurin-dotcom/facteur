import 'package:flutter/material.dart';

import '../../../config/theme.dart';

/// Transition text between two editorial subjects (N2).
///
/// Short linking text like "Pendant ce temps, côté tech…"
/// with thin separator lines above and below.
class TransitionText extends StatelessWidget {
  final String text;

  const TransitionText({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final separator = Container(
      height: 1,
      color: colors.textTertiary.withValues(alpha: 0.2),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          separator,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              text,
              style: FacteurTypography.bodySmall(colors.textSecondary)
                  .copyWith(fontStyle: FontStyle.italic),
              textAlign: TextAlign.center,
            ),
          ),
          separator,
        ],
      ),
    );
  }
}
