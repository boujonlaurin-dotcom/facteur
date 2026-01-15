import 'package:cached_network_image/cached_network_image.dart';
import 'package:facteur/config/theme.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/widgets/design/facteur_card.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

class FeedCard extends StatelessWidget {
  final Content content;
  final VoidCallback? onTap;
  final VoidCallback? onBookmark;
  final VoidCallback? onMoreOptions;
  final bool isBookmarked;
  final IconData? bookmarkIcon;

  const FeedCard({
    super.key,
    required this.content,
    this.onTap,
    this.onBookmark,
    this.onMoreOptions,
    this.isBookmarked = false,
    this.bookmarkIcon,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return FacteurCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Image (Header)
          if (content.thumbnailUrl != null && content.thumbnailUrl!.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(FacteurRadius.large)),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: CachedNetworkImage(
                  imageUrl: content.thumbnailUrl!,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: colors.backgroundSecondary,
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.primary.withOpacity(0.5),
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: colors.backgroundSecondary,
                    child: Icon(
                      PhosphorIcons.imageBroken(PhosphorIconsStyle.duotone),
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),

          // 2. Body (Title + Meta)
          Padding(
            padding: const EdgeInsets.all(FacteurSpacing.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Titre
                Text(
                  content.title,
                  style: textTheme.displaySmall?.copyWith(
                    fontSize: 21,
                    height: 1.3,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: FacteurSpacing.space2),
                // Métadonnées (Type • Durée)
                Row(
                  children: [
                    _buildTypeIcon(context, content.contentType),
                    const SizedBox(width: FacteurSpacing.space2),
                    if (content.durationSeconds != null)
                      Text(
                        _formatDuration(content.durationSeconds!),
                        style: textTheme.labelSmall?.copyWith(
                            color: colors.textSecondary,
                            fontWeight: FontWeight.w500),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // 3. Footer (Source + Actions)
          Container(
            decoration: BoxDecoration(
              color: colors.backgroundSecondary.withOpacity(0.5),
              border: Border(
                top: BorderSide(
                  color: colors.textSecondary.withOpacity(0.1),
                  width: 1,
                ),
              ),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: FacteurSpacing.space4,
              vertical: FacteurSpacing.space2,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      // Source Logo
                      if (content.source.logoUrl != null &&
                          content.source.logoUrl!.isNotEmpty) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: CachedNetworkImage(
                            imageUrl: content.source.logoUrl!,
                            width: 16,
                            height: 16,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) =>
                                _buildSourcePlaceholder(colors),
                          ),
                        ),
                        const SizedBox(width: FacteurSpacing.space2),
                      ] else ...[
                        _buildSourcePlaceholder(colors),
                        const SizedBox(width: FacteurSpacing.space2),
                      ],

                      // Source Name
                      Flexible(
                        flex: 2,
                        fit: FlexFit.loose,
                        child: Text(
                          content.source.name,
                          style: textTheme.labelMedium?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                      // Récence
                      const SizedBox(width: FacteurSpacing.space2),
                      Text(
                        timeago
                            .format(content.publishedAt, locale: 'fr_short')
                            .replaceAll('il y a ', ''),
                        style: textTheme.labelSmall?.copyWith(
                          color: colors.textSecondary,
                          fontSize: 11,
                        ),
                      ),

                      // Recommendation Badge (Optional)
                      if (content.recommendationReason != null) ...[
                        const SizedBox(width: FacteurSpacing.space2),
                        Text(
                          '•',
                          style: textTheme.labelSmall?.copyWith(
                            color: colors.textSecondary.withOpacity(0.5),
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(width: FacteurSpacing.space2),
                        Flexible(
                          flex: 3,
                          fit: FlexFit.loose,
                          child: Text(
                            content.recommendationReason!.label,
                            style: textTheme.labelSmall?.copyWith(
                              color: colors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Actions (Fixed on the right)
                InkWell(
                  key: const Key('feed_card_bookmark_button'),
                  onTap: onBookmark,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Icon(
                      bookmarkIcon ??
                          (isBookmarked
                              ? PhosphorIcons.clockClockwise(
                                  PhosphorIconsStyle.fill)
                              : PhosphorIcons.clockClockwise(
                                  PhosphorIconsStyle.regular)),
                      color:
                          isBookmarked ? colors.primary : colors.textSecondary,
                      size: 20,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    PhosphorIcons.dotsThree(PhosphorIconsStyle.bold),
                    color: colors.textSecondary,
                    size: 20,
                  ),
                  onPressed: onMoreOptions,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.all(8),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourcePlaceholder(FacteurColors colors) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Text(
          content.source.name.isNotEmpty
              ? content.source.name.substring(0, 1).toUpperCase()
              : '?',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: colors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildTypeIcon(BuildContext context, ContentType type) {
    final colors = context.facteurColors;
    IconData icon;

    switch (type) {
      case ContentType.video:
      case ContentType.youtube:
        icon = PhosphorIcons.filmStrip(PhosphorIconsStyle.fill);
        break;
      case ContentType.audio:
        icon = PhosphorIcons.headphones(PhosphorIconsStyle.fill);
        break;
      default:
        // No icon for articles to reduce clutter
        return const SizedBox.shrink();
    }

    return Icon(icon, size: 14, color: colors.textSecondary);
  }

  /* 
  String _getThemeDisplayName(String themeCode) {
    switch (themeCode.toLowerCase()) {
      case 'tech':
        return 'TECH & FUTUR';
      case 'geopolitics':
        return 'GÉOPOLITIQUE';
      case 'economy':
        return 'ÉCONOMIE';
      case 'society_climate':
        return 'SOCIÉTÉ & CLIMAT';
      case 'culture_ideas':
        return 'CULTURE & IDÉES';
      default:
        return themeCode.toUpperCase();
    }
  }
  */

  String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final minutes = (seconds / 60).ceil();
    return '$minutes min';
  }
}
