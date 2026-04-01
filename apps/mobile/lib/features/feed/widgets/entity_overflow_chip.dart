import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../models/content_model.dart';
import '../providers/feed_provider.dart';
import 'keyword_overflow_chip.dart';

/// Chip shown below the representative card of an entity group.
///
/// Displays: `> Entity — N articles   [logo1 logo2 logo3 +N] >`
/// Tap filters the feed by the entity via setEntity().
class EntityOverflowChip extends ConsumerWidget {
  final Content content;
  final VoidCallback? onOverflowTap;

  const EntityOverflowChip({
    super.key,
    required this.content,
    this.onOverflowTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (content.entityOverflowCount == 0) {
      return const SizedBox.shrink();
    }

    final colors = context.facteurColors;
    final sources = content.entityOverflowSources;

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
        ref.read(feedProvider.notifier).setEntity(content.entityOverflowKey!);
        onOverflowTap?.call();
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
                content.entityOverflowLabel ?? '',
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
