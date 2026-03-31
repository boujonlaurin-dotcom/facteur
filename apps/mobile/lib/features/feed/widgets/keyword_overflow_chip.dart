import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../widgets/design/facteur_image.dart';
import '../models/content_model.dart';
import '../providers/feed_provider.dart';
import 'initial_circle.dart';

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
        // Filter feed by keyword (title ILIKE match)
        ref.read(feedProvider.notifier).setKeyword(content.keywordOverflowKey!);
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
                  if (isSingleSource && sortedSources.isNotEmpty) ...[
                    const SizedBox(width: FacteurSpacing.space2),
                    _SourceLogo(
                      source: sortedSources.first,
                      colors: colors,
                    ),
                  ],
                  if (!isSingleSource && sortedSources.isNotEmpty) ...[
                    const SizedBox(width: FacteurSpacing.space2),
                    _SourceLogos(sources: sortedSources, colors: colors),
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

/// Single source: circular logo + "de {sourceName}".
class _SourceLogo extends StatelessWidget {
  final KeywordOverflowSource source;
  final FacteurColors colors;

  const _SourceLogo({required this.source, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LogoCircle(source: source, colors: colors),
      ],
    );
  }
}

/// Multi-source: up to 3 circular logos with tight spacing + optional "+N".
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
          _LogoCircle(source: visibleSources[i], colors: colors),
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

/// A single circular logo (14x14). Shows the source image if available,
/// otherwise falls back to the source's initial letter in a colored circle.
class _LogoCircle extends StatelessWidget {
  final KeywordOverflowSource source;
  final FacteurColors colors;

  const _LogoCircle({required this.source, required this.colors});

  @override
  Widget build(BuildContext context) {
    final hasLogo = source.sourceLogoUrl != null &&
        source.sourceLogoUrl!.isNotEmpty;

    if (hasLogo) {
      return ClipOval(
        child: FacteurImage(
          imageUrl: source.sourceLogoUrl!,
          width: 14,
          height: 14,
          fit: BoxFit.cover,
          errorWidget: (context) => InitialCircle(
            initial: source.sourceName.isNotEmpty
                ? source.sourceName[0].toUpperCase()
                : '?',
            colors: colors,
          ),
        ),
      );
    }

    return InitialCircle(
      initial: source.sourceName.isNotEmpty
          ? source.sourceName[0].toUpperCase()
          : '?',
      colors: colors,
    );
  }
}


