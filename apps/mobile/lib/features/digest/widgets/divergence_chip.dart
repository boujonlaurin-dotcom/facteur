import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../config/theme.dart';

/// Chip displaying the divergence level between media perspectives.
/// Returns SizedBox.shrink() when [divergenceLevel] is null.
class DivergenceChip extends StatelessWidget {
  final String? divergenceLevel;

  const DivergenceChip({super.key, this.divergenceLevel});

  @override
  Widget build(BuildContext context) {
    if (divergenceLevel == null) return const SizedBox.shrink();

    final colors = context.facteurColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final (IconData icon, String label, Color color) = switch (divergenceLevel!) {
      'high' => (PhosphorIcons.lightning(), 'Fort désaccord', colors.error),
      'medium' => (PhosphorIcons.arrowsLeftRight(), 'Angles différents', colors.warning),
      _ => (PhosphorIcons.equals(), 'Traitements similaires', colors.success),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.15 : 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
