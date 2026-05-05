import 'package:facteur/config/theme.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../models/content_model.dart';

/// Badge showing reading progress level on article cards.
///
/// Levels:
/// - "Parcouru" (< 30%) — neutral gray
/// - "Lu" (30-89%) — green with single check
/// - "Lu jusqu'au bout" (>= 90%) — green with double check
class ReadingBadge extends StatelessWidget {
  final Content content;

  const ReadingBadge({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    final label = content.readingLabel;
    if (label == null) return const SizedBox.shrink();

    final colors = context.facteurColors;
    final progress = content.readingProgress;
    final isConsumed = content.status == ContentStatus.consumed;

    // Color logic
    final Color bgColor;
    final Color fgColor;
    final IconData icon;

    if (progress >= 90) {
      // Lu jusqu'au bout — strong green + double check
      bgColor = colors.success;
      fgColor = Colors.white;
      icon = PhosphorIcons.checks(PhosphorIconsStyle.bold);
    } else if (progress >= 30 || isConsumed) {
      // Lu — green + check circle (also covers freshly-opened articles
      // where status==consumed but scroll progress is still 0)
      bgColor = colors.success;
      fgColor = Colors.white;
      icon = PhosphorIcons.checkCircle(PhosphorIconsStyle.fill);
    } else {
      // Parcouru — neutral gray
      bgColor = colors.textSecondary.withOpacity(0.7);
      fgColor = Colors.white;
      icon = PhosphorIcons.eye(PhosphorIconsStyle.regular);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fgColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: fgColor,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
