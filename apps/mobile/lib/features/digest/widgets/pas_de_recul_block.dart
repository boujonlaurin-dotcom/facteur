import 'package:flutter/material.dart';
import '../../../config/theme.dart';
import '../models/digest_models.dart';
import 'editorial_badge.dart';

/// Companion block for the deep analysis article ("Pas de recul").
/// Displayed in the expanded toggle state of a topic.
class PasDeReculBlock extends StatelessWidget {
  final DigestItem deepArticle;
  final VoidCallback? onTap;

  const PasDeReculBlock({
    super.key,
    required this.deepArticle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final badgeChip = EditorialBadge.chip('pas_de_recul', context: context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.textSecondary.withValues(alpha: isDark ? 0.08 : 0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Badge
            if (badgeChip != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: badgeChip,
              ),

            // Article title
            Text(
              deepArticle.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : colors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),

            // Source + read CTA
            Row(
              children: [
                if (deepArticle.source?.name != null)
                  Text(
                    deepArticle.source!.name,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.5)
                          : colors.textSecondary.withValues(alpha: 0.7),
                    ),
                  ),
                if (deepArticle.source?.name != null)
                  Text(
                    ' \u00b7 ',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textSecondary.withValues(alpha: 0.5),
                    ),
                  ),
                Text(
                  'Lire \u2192',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.info,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
