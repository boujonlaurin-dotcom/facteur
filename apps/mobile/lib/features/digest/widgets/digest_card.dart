import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../config/theme.dart';
import '../../../widgets/design/facteur_card.dart';
import '../models/digest_models.dart';
import '../../feed/models/content_model.dart' show ContentType;
import 'article_action_bar.dart';

/// Digest card widget displaying a single digest article
/// Adapted from FeedCard with additional rank indicator and action bar
class DigestCard extends StatelessWidget {
  final DigestItem item;
  final VoidCallback? onTap;
  final ValueChanged<String>? onAction;

  const DigestCard({
    super.key,
    required this.item,
    this.onTap,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    final isProcessed = item.isRead || item.isDismissed;
    final badgeText = item.isRead ? 'Lu' : (item.isDismissed ? 'Masqué' : null);
    final badgeColor = item.isRead ? colors.success : colors.textSecondary;

    return Opacity(
      opacity: isProcessed ? 0.6 : 1.0,
      child: Stack(
        children: [
          FacteurCard(
            onTap: onTap,
            padding: EdgeInsets.zero,
            borderRadius: FacteurRadius.small,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Thumbnail with rank badge overlay
                if (item.thumbnailUrl != null && item.thumbnailUrl!.isNotEmpty)
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(FacteurRadius.small)),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: CachedNetworkImage(
                        imageUrl: item.thumbnailUrl!,
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

                // 2. Body (Title + Meta + Reason)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FacteurSpacing.space3,
                    vertical: FacteurSpacing.space3,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Selection reason badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _simplifyReason(item.reason),
                          style: TextStyle(
                            color: colors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: FacteurSpacing.space2),

                      // Title
                      Text(
                        item.title,
                        style: textTheme.displaySmall?.copyWith(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),

                      if ((item.thumbnailUrl == null ||
                              item.thumbnailUrl!.isEmpty) &&
                          item.description != null &&
                          item.description!.isNotEmpty) ...[
                        const SizedBox(height: FacteurSpacing.space2),
                        Text(
                          item.description!,
                          style: textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary.withValues(alpha: 0.8),
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],

                      const SizedBox(height: FacteurSpacing.space2),

                      // Type + Duration
                      Row(
                        children: [
                          _buildTypeIcon(context, item.contentType),
                          const SizedBox(width: FacteurSpacing.space2),
                          if (item.durationSeconds != null)
                            Text(
                              _formatDuration(item.durationSeconds!),
                              style: textTheme.labelSmall?.copyWith(
                                color: colors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                // 3. Footer (Source row)
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
                    vertical: FacteurSpacing.space2,
                  ),
                  child: Row(
                    children: [
                      // Source Logo
                      if (item.source?.logoUrl != null &&
                          item.source!.logoUrl!.isNotEmpty) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: CachedNetworkImage(
                            imageUrl: item.source!.logoUrl!,
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
                          item.source?.name ?? 'Source inconnue',
                          style: textTheme.labelMedium?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                      // Recency
                      const SizedBox(width: FacteurSpacing.space2),
                      Text(
                        item.publishedAt != null
                            ? timeago
                                .format(item.publishedAt!, locale: 'fr_short')
                                .replaceAll('il y a ', '')
                            : '--',
                        style: textTheme.labelSmall?.copyWith(
                          color: colors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),

                // 4. Action Bar
                if (onAction != null)
                  ArticleActionBar(
                    item: item,
                    onAction: onAction!,
                  ),
              ],
            ),
          ),

          // Rank badge (top-left)
          Positioned(
            top: 12,
            left: 12,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: colors.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  '${item.rank}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),

          // Processed badge (top-right)
          if (badgeText != null)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      PhosphorIcons.check(PhosphorIconsStyle.bold),
                      size: 12,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      badgeText,
                      style: const TextStyle(
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
          (item.source?.name ?? '').isNotEmpty
              ? item.source!.name.substring(0, 1).toUpperCase()
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

  static String _simplifyReason(String reason) {
    var r = reason;
    r = r.replaceAll(RegExp(r'\s*\(\+\d+\s*pts\)'), '');
    if (r.contains(':')) r = r.split(':').first.trim();
    r = r.replaceAll(RegExp(r'\s+depuis\s+.*', caseSensitive: false), '');
    return r.trim();
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final minutes = (seconds / 60).ceil();
    return '$minutes min';
  }
}
