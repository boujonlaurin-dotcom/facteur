import 'package:flutter/material.dart';

import '../../../config/theme.dart';

/// Visual divider "Et aussi…" between main subjects and pépite/coup de coeur (N4).
class DigestSectionDivider extends StatelessWidget {
  final String label;

  const DigestSectionDivider({
    super.key,
    this.label = 'Et aussi\u2026',
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.only(top: 32, bottom: 16),
      child: Column(
        children: [
          Text(
            label,
            style: FacteurTypography.displaySmall(colors.textPrimary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Container(
            height: 2,
            width: 60,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ],
      ),
    );
  }
}
