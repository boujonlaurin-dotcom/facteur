import 'package:flutter/material.dart';
import '../../../config/theme.dart';
import '../../../widgets/design/facteur_card.dart';
import '../../../widgets/design/facteur_thumbnail.dart';
import '../models/digest_models.dart';
import 'editorial_badge.dart';

/// Companion block for the deep analysis article ("Pas de recul").
/// Displayed in the expanded toggle state of a topic.
class PasDeReculBlock extends StatelessWidget {
  final DigestItem deepArticle;
  final String? reculIntro;
  final VoidCallback? onTap;

  const PasDeReculBlock({
    super.key,
    required this.deepArticle,
    this.reculIntro,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final badgeChip = EditorialBadge.chip('pas_de_recul', context: context);

    return FacteurCard(
      onTap: onTap,
      backgroundColor: colors.info.withValues(alpha: isDark ? 0.25 : 0.22),
      padding: EdgeInsets.zero,
      borderRadius: 12,
      boxShadow: const [],
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(width: 3, color: colors.info),
          ),
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

            // Recul intro
            if (reculIntro != null) ...[
              Text(
                reculIntro!,
                style: TextStyle(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.85)
                      : colors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
            ],

            // Title + thumbnail row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title + source
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        deepArticle.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),

                      // Source + arrow
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
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_ios,
                            size: 12,
                            color: colors.info,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Thumbnail
                const SizedBox(width: 12),
                SizedBox(
                  width: 60,
                  height: 60,
                  child: FacteurThumbnail(
                    imageUrl: deepArticle.thumbnailUrl,
                    aspectRatio: 1.0,
                    borderRadius: BorderRadius.circular(8),
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
