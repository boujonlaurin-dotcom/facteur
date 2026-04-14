import 'package:flutter/material.dart';
import '../../../config/theme.dart';

/// Visual divider "Et aussi…" between main topics and special picks (N4).
class SectionDivider extends StatelessWidget {
  final String label;

  const SectionDivider({super.key, this.label = 'Et aussi…'});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF2C1E10);

    return Padding(
      padding: const EdgeInsets.only(top: 32, bottom: 16),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 60,
              height: 2,
              color: colors.primary.withOpacity(0.3),
            ),
          ),
        ],
      ),
    );
  }
}
