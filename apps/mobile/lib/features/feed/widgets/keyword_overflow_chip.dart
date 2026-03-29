import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../widgets/design/facteur_image.dart';
import '../models/content_model.dart';
import '../providers/feed_provider.dart';

/// Chip shown below the representative card of a keyword group.
///
/// Displays: `> Keyword — N articles [de Source | logos×3 +X]`
/// Tap filters the feed by the keyword via setTopic().
class KeywordOverflowChip extends ConsumerWidget {
  final Content content;

  const KeywordOverflowChip({
    super.key,
    required this.content,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (content.keywordOverflowCount == 0) {
      return const SizedBox.shrink();
    }

    final colors = context.facteurColors;
    final sources = content.keywordOverflowSources;
    final isSingleSource = sources.length == 1;

    return GestureDetector(
      onTap: () {
        // Filter feed by keyword (reuse topic filter mechanism)
        ref.read(feedProvider.notifier).setTopic(content.keywordOverflowKey!);
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
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      content.keywordOverflowLabel ?? '',
                      style:
                          Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: colors.textSecondary,
                              ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!isSingleSource && sources.isNotEmpty) ...[
                    const SizedBox(width: FacteurSpacing.space2),
                    _SourceLogos(sources: sources, colors: colors),
                  ],
                ],
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

class _SourceLogos extends StatelessWidget {
  final List<KeywordOverflowSource> sources;
  final FacteurColors colors;

  const _SourceLogos({required this.sources, required this.colors});

  @override
  Widget build(BuildContext context) {
    const maxLogos = 3;
    final visibleSources = sources.take(maxLogos).toList();
    final extraCount = sources.length - maxLogos;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < visibleSources.length; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: visibleSources[i].sourceLogoUrl != null &&
                    visibleSources[i].sourceLogoUrl!.isNotEmpty
                ? FacteurImage(
                    imageUrl: visibleSources[i].sourceLogoUrl!,
                    width: 16,
                    height: 16,
                    fit: BoxFit.cover,
                    errorWidget: (context) =>
                        const SizedBox(width: 16, height: 16),
                  )
                : const SizedBox(width: 16, height: 16),
          ),
        ],
        if (extraCount > 0) ...[
          const SizedBox(width: 2),
          Text(
            '+$extraCount',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.textTertiary,
                  fontSize: 10,
                ),
          ),
        ],
      ],
    );
  }
}
