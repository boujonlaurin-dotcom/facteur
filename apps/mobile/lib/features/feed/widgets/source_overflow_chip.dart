import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../widgets/design/facteur_image.dart';
import '../models/content_model.dart';
import '../providers/feed_provider.dart';

/// Chip shown below the last card of a source when diversification filtered articles.
///
/// Displays: `> N autres articles de [Source]`
/// Tap filters the feed to show all articles from that source.
class SourceOverflowChip extends ConsumerWidget {
  final Content content;

  const SourceOverflowChip({
    super.key,
    required this.content,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (content.sourceOverflowCount == 0) {
      return const SizedBox.shrink();
    }

    final colors = context.facteurColors;

    return GestureDetector(
      onTap: () {
        ref.read(feedProvider.notifier).setSource(content.source.id);
      },
      child: Container(
        decoration: BoxDecoration(
          color: Color.lerp(colors.backgroundSecondary, Colors.black, 0.03)!,
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
              color: colors.textSecondary,
            ),
            const SizedBox(width: FacteurSpacing.space2),
            if (content.source.logoUrl != null &&
                content.source.logoUrl!.isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: FacteurImage(
                  imageUrl: content.source.logoUrl!,
                  width: 16,
                  height: 16,
                  fit: BoxFit.cover,
                  errorWidget: (context) =>
                      const SizedBox(width: 16, height: 16),
                ),
              ),
              const SizedBox(width: FacteurSpacing.space1),
            ],
            Expanded(
              child: Text(
                '${content.sourceOverflowCount} autres articles de \u2022 ${content.source.name}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
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
