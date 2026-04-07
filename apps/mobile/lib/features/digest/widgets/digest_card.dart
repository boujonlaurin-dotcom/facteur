import 'package:facteur/core/utils/html_utils.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../config/theme.dart';
import '../../../widgets/design/facteur_card.dart';
import '../../../widgets/design/facteur_image.dart';
import '../../../widgets/design/facteur_thumbnail.dart';
import '../../../widgets/design/video_play_overlay.dart';
import '../models/digest_models.dart';
import '../../feed/models/content_model.dart' show ContentType;
import 'article_action_bar.dart';

/// Digest card widget displaying a single digest article
/// Adapted from FeedCard with additional rank indicator and action bar
class DigestCard extends StatelessWidget {
  final DigestItem item;
  final VoidCallback? onTap;
  final ValueChanged<String>? onAction;
  final bool isSerene;

  const DigestCard({
    super.key,
    required this.item,
    this.onTap,
    this.onAction,
    this.isSerene = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final isProcessed = item.isRead || item.isDismissed;
    final isVideo = item.contentType == ContentType.youtube || item.contentType == ContentType.video;
    final isShort = isVideo && item.url.contains('/shorts/');
    final badgeText = item.isRead
        ? (isVideo ? 'Vu' : 'Lu')
        : (item.isDismissed ? 'Masqué' : null);
    final badgeColor = item.isRead ? colors.success : colors.textSecondary;
    final hasNote =
        item.noteText != null && item.noteText!.isNotEmpty;

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
                // Red accent line for video cards
                if (isVideo)
                  Container(
                    height: 3,
                    color: const Color(0xFFFF0000),
                  ),

                // 1. Thumbnail with rank badge overlay
                FacteurThumbnail(
                  imageUrl: item.thumbnailUrl,
                  borderRadius: isVideo
                      ? BorderRadius.zero
                      : const BorderRadius.vertical(
                          top: Radius.circular(FacteurRadius.small)),
                  overlay: isVideo ? const VideoPlayOverlay() : null,
                  durationLabel: isVideo && item.durationSeconds != null
                      ? _formatDuration(item.durationSeconds!)
                      : null,
                  isVideo: isVideo,
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
                      // Badge: editorial semantic badge or fallback reason badge
                      _buildBadge(colors, isDark),
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
                          stripHtml(item.description!),
                          style: textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary.withValues(alpha: 0.8),
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],

                      const SizedBox(height: FacteurSpacing.space2),

                      // Type + Duration + Short badge
                      Row(
                        children: [
                          _buildTypeIcon(context, item.contentType),
                          const SizedBox(width: FacteurSpacing.space2),
                          if (isShort)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              margin: const EdgeInsets.only(
                                  right: FacteurSpacing.space2),
                              decoration: BoxDecoration(
                                color: colors.textSecondary
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Short',
                                style: textTheme.labelSmall?.copyWith(
                                  color: colors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 10,
                                ),
                              ),
                            ),
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
                          child: FacteurImage(
                            imageUrl: item.source!.logoUrl!,
                            width: 16,
                            height: 16,
                            fit: BoxFit.cover,
                            errorWidget: (context) =>
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

                      // Paywall badge
                      if (item.isPaid) ...[
                        const SizedBox(width: FacteurSpacing.space2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: colors.warning.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                PhosphorIcons.lock(PhosphorIconsStyle.fill),
                                size: 10,
                                color: colors.warning,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                'Payant',
                                style: TextStyle(
                                  color: colors.warning,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // 4. Action Bar
                if (onAction != null)
                  ArticleActionBar(
                    item: item,
                    onAction: onAction!,
                    isSerene: isSerene,
                  ),
              ],
            ),
          ),

          // Rank badge (top-left) — hidden in editorial mode
          if (item.badge == null)
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

          // Processed / note badges (top-right)
          if (badgeText != null || hasNote)
            Positioned(
              top: 12,
              right: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (badgeText != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
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
                  if (hasNote) ...[
                    if (badgeText != null) const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: colors.primary,
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
                            PhosphorIcons.pencilLine(
                                PhosphorIconsStyle.fill),
                            size: 12,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'Article annoté',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Builds the editorial semantic badge or falls back to the reason badge.
  Widget _buildBadge(FacteurColors colors, bool isDark) {
    if (item.badge != null) {
      final config = _badgeConfig(item.badge!, isDark, colors);
      if (config != null) {
        final showEmoji = !isSerene ||
            item.badge == 'pepite' ||
            item.badge == 'coup_de_coeur';
        final label = showEmoji && config.emoji.isNotEmpty
            ? '${config.emoji} ${config.label}'
            : config.label;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: config.backgroundColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: config.textColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }
    }
    // Fallback: algorithmic reason badge
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
    );
  }

  static _BadgeConfig? _badgeConfig(
      String badge, bool isDark, FacteurColors colors) {
    final alpha = isDark ? 0.15 : 0.10;
    switch (badge) {
      case 'actu':
        return _BadgeConfig(
          emoji: '',
          label: "L'actu du jour",
          backgroundColor: colors.primary.withValues(alpha: alpha * 0.7),
          textColor: colors.primary,
        );
      case 'pas_de_recul':
        return _BadgeConfig(
          emoji: '🔭',
          label: 'Le pas de recul',
          backgroundColor: colors.info.withValues(alpha: alpha),
          textColor: colors.info,
        );
      case 'pepite':
        return _BadgeConfig(
          emoji: '🍀',
          label: 'Pépite du jour',
          backgroundColor: colors.success.withValues(alpha: alpha),
          textColor: colors.success,
        );
      case 'coup_de_coeur':
        return _BadgeConfig(
          emoji: '💚',
          label: 'Coup de cœur',
          backgroundColor: colors.success.withValues(alpha: alpha),
          textColor: colors.success,
        );
      default:
        return null;
    }
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
        // Play overlay + red accent line suffice as video indicator
        return const SizedBox.shrink();
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
    // Remove points notation
    r = r.replaceAll(RegExp(r'\s*\(\+\d+\s*pts?\)'), '');
    // Remove "depuis..." suffix
    r = r.replaceAll(RegExp(r'\s+depuis\s+.*', caseSensitive: false), '');

    // Extract theme name if it's a theme-based reason (e.g., "Thème : Environnement")
    if (r.contains(':')) {
      final parts = r.split(':');
      if (parts.isNotEmpty) {
        r = parts.last.trim();
      }
    }

    // Return only the theme/category name, default to "Environnement"
    return r.trim().isEmpty ? 'Environnement' : r.trim();
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final minutes = (seconds / 60).ceil();
    return '$minutes min';
  }
}

class _BadgeConfig {
  final String emoji;
  final String label;
  final Color backgroundColor;
  final Color textColor;

  const _BadgeConfig({
    required this.emoji,
    required this.label,
    required this.backgroundColor,
    required this.textColor,
  });
}
