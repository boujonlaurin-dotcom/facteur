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
  final VoidCallback? onPersonalize;
  final VoidCallback? onSave;
  final VoidCallback? onLike;
  final VoidCallback? onNotInterested;
  final bool isSaved;
  final bool isLiked;

  const FeedCard({
    super.key,
    required this.content,
    this.onTap,
    this.onPersonalize,
    this.onSave,
    this.onLike,
    this.onNotInterested,
    this.isSaved = false,
    this.isLiked = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    final isConsumed = content.status == ContentStatus.consumed;

    return Opacity(
      opacity: isConsumed ? 0.6 : 1.0,
      child: Stack(
        children: [
          FacteurCard(
            onTap: onTap,
            padding: EdgeInsets.zero,
            borderRadius: FacteurRadius.small,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Image (Header)
                if (content.thumbnailUrl != null &&
                    content.thumbnailUrl!.isNotEmpty)
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(FacteurRadius.small)),
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
                              color: colors.primary.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: colors.backgroundSecondary,
                          child: Icon(
                            PhosphorIcons.imageBroken(
                                PhosphorIconsStyle.duotone),
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),

                // 2. Body (Title + Meta)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FacteurSpacing.space3,
                    vertical: FacteurSpacing.space3,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Titre
                      Text(
                        content.title,
                        style: textTheme.displaySmall?.copyWith(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if ((content.thumbnailUrl == null ||
                              content.thumbnailUrl!.isEmpty) &&
                          content.description != null &&
                          content.description!.isNotEmpty) ...[
                        const SizedBox(height: FacteurSpacing.space2),
                        Text(
                          content.description!,
                          style: textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary.withValues(alpha: 0.8),
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
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
                    color: colors.backgroundSecondary.withValues(alpha: 0.5),
                    border: Border(
                      top: BorderSide(
                        color: colors.textSecondary.withValues(alpha: 0.1),
                        width: 1,
                      ),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: FacteurSpacing.space3,
                    vertical: FacteurSpacing.space1,
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
                                  .format(content.publishedAt,
                                      locale: 'fr_short')
                                  .replaceAll('il y a ', ''),
                              style: textTheme.labelSmall?.copyWith(
                                color: colors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Actions (Like, Save, NotInterested, Personalize)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Like button
                          if (onLike != null)
                            InkWell(
                              onTap: onLike,
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                child: Icon(
                                  isLiked
                                      ? PhosphorIcons.heart(
                                          PhosphorIconsStyle.fill)
                                      : PhosphorIcons.heart(),
                                  size: 20,
                                  color: isLiked
                                      ? colors.primary
                                      : colors.textSecondary,
                                ),
                              ),
                            ),

                          // Save button
                          if (onSave != null)
                            InkWell(
                              onTap: onSave,
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                child: Icon(
                                  isSaved
                                      ? PhosphorIcons.bookmark(
                                          PhosphorIconsStyle.fill)
                                      : PhosphorIcons.bookmark(),
                                  size: 20,
                                  color: isSaved
                                      ? colors.primary
                                      : colors.textSecondary,
                                ),
                              ),
                            ),

                          // NotInterested button
                          if (onNotInterested != null)
                            InkWell(
                              onTap: onNotInterested,
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                child: Icon(
                                  PhosphorIcons.eyeSlash(),
                                  size: 20,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ),

                          // Personalize button (for Feed)
                          if (onPersonalize != null)
                            InkWell(
                              onTap: onPersonalize,
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 4),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      PhosphorIcons.question(
                                          PhosphorIconsStyle.regular),
                                      size: 14,
                                      color: colors.textTertiary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Personnalisation',
                                      style: textTheme.labelSmall?.copyWith(
                                        color: colors.textTertiary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (isConsumed)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.success,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check,
                      size: 12,
                      color: Colors.white,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Lu',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
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
