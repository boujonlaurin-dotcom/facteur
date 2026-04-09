import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../models/content_model.dart';
import '../providers/feed_provider.dart';
import 'keyword_overflow_chip.dart';

/// Chip shown below the last card of a source when diversification filtered articles.
///
/// Displays: `> N articles récents de [Source]   [logo] >`
/// Tap filters the feed to show all articles from that source.
class SourceOverflowChip extends ConsumerWidget {
  final Content content;
  final VoidCallback? onOverflowTap;

  const SourceOverflowChip({
    super.key,
    required this.content,
    this.onOverflowTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (content.sourceOverflowCount == 0) {
      return const SizedBox.shrink();
    }

    final colors = context.facteurColors;
    final sourceAsBadge = KeywordOverflowSource(
      sourceId: content.source.id,
      sourceName: content.source.name,
      sourceLogoUrl: content.source.logoUrl,
      articleCount: content.sourceOverflowCount,
    );

    return GestureDetector(
      onTap: () {
        ref.read(feedProvider.notifier).setSource(content.source.id);
        onOverflowTap?.call();
      },
      child: Container(
        decoration: BoxDecoration(
          color: colors.backgroundSecondary,
          border: Border(
            top: BorderSide(
              color: colors.textSecondary.withValues(alpha: 0.1),
              width: 0.5,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: FacteurSpacing.space3,
          vertical: FacteurSpacing.space2,
        ),
        child: Row(
          children: [
            Icon(
              PhosphorIcons.caretRight(PhosphorIconsStyle.bold),
              size: 12,
              color: colors.textTertiary,
            ),
            const SizedBox(width: FacteurSpacing.space2),
            Expanded(
              child: Text(
                '${content.sourceOverflowCount} articles récents de ${content.source.name}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colors.textTertiary,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: FacteurSpacing.space2),
            LogoCircle(source: sourceAsBadge, colors: colors),
            const SizedBox(width: FacteurSpacing.space2),
            Icon(
              PhosphorIcons.arrowRight(),
              size: 14,
              color: colors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
