import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../models/content_model.dart';
import '../providers/feed_provider.dart';
import 'keyword_overflow_chip.dart';

/// Chip shown below the last card of a neutral topic/theme group when
/// topic-aware regroupement compressed articles.
///
/// Displays: `> N autres articles {label}   [logo1 logo2 ...+N] >`
/// Tap filters the feed by theme or topic depending on group_type.
class TopicOverflowChip extends ConsumerWidget {
  final Content content;

  const TopicOverflowChip({
    super.key,
    required this.content,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (content.topicOverflowCount == 0) {
      return const SizedBox.shrink();
    }

    final colors = context.facteurColors;
    final sources = content.topicOverflowSources;

    // Sort sources so those with logos come first
    final sortedSources = List<KeywordOverflowSource>.from(sources)
      ..sort((a, b) {
        final aHasLogo =
            a.sourceLogoUrl != null && a.sourceLogoUrl!.isNotEmpty ? 0 : 1;
        final bHasLogo =
            b.sourceLogoUrl != null && b.sourceLogoUrl!.isNotEmpty ? 0 : 1;
        return aHasLogo.compareTo(bHasLogo);
      });

    return GestureDetector(
      onTap: () {
        if (content.topicOverflowType == 'topic') {
          ref.read(feedProvider.notifier).setTopic(content.topicOverflowKey!);
        } else {
          ref.read(feedProvider.notifier).setTheme(content.topicOverflowKey!);
        }
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
              child: Text(
                '${content.topicOverflowCount} autres articles ${content.topicOverflowLabel}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (sortedSources.isNotEmpty) ...[
              const SizedBox(width: FacteurSpacing.space2),
              SourceLogos(sources: sortedSources, colors: colors),
            ],
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
