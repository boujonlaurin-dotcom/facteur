import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../config/theme.dart';
import '../../../widgets/design/facteur_card.dart';
import '../models/content_model.dart';
import 'package:cached_network_image/cached_network_image.dart';

class BriefingCard extends StatelessWidget {
  final DailyTop3Item item;
  final VoidCallback onTap;
  final VoidCallback? onPersonalize;

  const BriefingCard({
    super.key,
    required this.item,
    required this.onTap,
    this.onPersonalize,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: onTap,
      child: FacteurCard(
        padding: EdgeInsets.zero,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Rank & Reason strip
              Container(
                width: 48,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.1),
                  border: Border(
                    right: BorderSide(
                      color: colors.textSecondary.withValues(alpha: 0.2),
                      width: 1,
                    ),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '#${item.rank}',
                      style: textTheme.titleLarge?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (item.isConsumed)
                      Icon(
                        PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
                        color: colors.primary,
                        size: 20,
                      )
                  ],
                ),
              ),

              // 2. Content Info
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Badge Reason
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color:
                                  colors.textSecondary.withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          item.reason.toUpperCase(),
                          style: textTheme.labelSmall?.copyWith(
                            color: colors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Title
                      Text(
                        item.content.title,
                        style: textTheme.titleMedium?.copyWith(
                          color: item.isConsumed
                              ? colors.textSecondary
                              : colors.textPrimary,
                          decoration: item.isConsumed
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Spacer(),
                      // Source meta
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (item.content.source.logoUrl != null)
                            CachedNetworkImage(
                              imageUrl: item.content.source.logoUrl!,
                              width: 16,
                              height: 16,
                              errorWidget: (_, __, ___) => const SizedBox(),
                            ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              item.content.source.name,
                              style: textTheme.labelSmall?.copyWith(
                                color: colors.textSecondary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            _formatDuration(item.content.publishedAt),
                            style: textTheme.labelSmall?.copyWith(
                              color: colors.textTertiary,
                            ),
                          ),
                          if (onPersonalize != null) ...[
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: onPersonalize,
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 2),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      PhosphorIcons.question(
                                          PhosphorIconsStyle.regular),
                                      size: 14,
                                      color: colors.textSecondary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Personnalisation',
                                      style: textTheme.labelSmall?.copyWith(
                                        color: colors.textSecondary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // 3. Image (optional)
              if (item.content.thumbnailUrl != null)
                SizedBox(
                  width: 100,
                  child: CachedNetworkImage(
                    imageUrl: item.content.thumbnailUrl!,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: colors.surface,
                      child: Icon(
                          PhosphorIcons.image(PhosphorIconsStyle.duotone),
                          color: colors.textTertiary),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: colors.surface,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inHours < 24) {
      return '${diff.inHours}h';
    } else {
      return '${diff.inDays}j';
    }
  }
}
