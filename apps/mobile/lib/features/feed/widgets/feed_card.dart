import 'package:facteur/config/theme.dart';
import 'package:facteur/core/utils/html_utils.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/feed/widgets/reading_badge.dart';
import 'package:facteur/widgets/design/facteur_card.dart';
import 'package:facteur/widgets/design/facteur_image.dart';
import 'package:facteur/widgets/design/facteur_thumbnail.dart';
import 'package:facteur/widgets/design/video_play_overlay.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

class FeedCard extends StatelessWidget {
  final Content content;
  final VoidCallback? onTap;
  final GestureLongPressStartCallback? onLongPressStart;
  final GestureLongPressMoveUpdateCallback? onLongPressMoveUpdate;
  final GestureLongPressEndCallback? onLongPressEnd;
  final VoidCallback? onSave;
  final VoidCallback? onSaveLongPress;
  final VoidCallback? onLike;
  final VoidCallback? onNotInterested;
  final VoidCallback? onReportNotSerene;
  final bool isSerene;
  final VoidCallback? onSourceTap; // Epic 12: tap source name/logo → detail
  final Widget? topicChipWidget;
  final Widget? clusterChipWidget;
  final bool isSaved;
  final bool isLiked;
  final bool isFollowedSource;
  final bool isSourceSubscribed;
  final bool hasActiveFilter; // Feed fallback: filtre thème/topic/entité actif
  final VoidCallback? onFollowSource; // Feed fallback: suivre la source
  final Color? backgroundColor;
  final List<BoxShadow>? boxShadow;
  final String? editorialBadgeLabel;
  final bool expandContent;
  final bool alwaysShowDescription;
  final VoidCallback? onImageError;
  final double? descriptionFontSize;

  const FeedCard({
    super.key,
    required this.content,
    this.onTap,
    this.onLongPressStart,
    this.onLongPressMoveUpdate,
    this.onLongPressEnd,
    this.onSave,
    this.onSaveLongPress,
    this.onLike,
    this.onNotInterested,
    this.onReportNotSerene,
    this.isSerene = false,
    this.onSourceTap,
    this.topicChipWidget,
    this.clusterChipWidget,
    this.isSaved = false,
    this.isLiked = false,
    this.isFollowedSource = false,
    this.isSourceSubscribed = false,
    this.hasActiveFilter = false,
    this.onFollowSource,
    this.backgroundColor,
    this.boxShadow,
    this.editorialBadgeLabel,
    this.expandContent = false,
    this.alwaysShowDescription = false,
    this.onImageError,
    this.descriptionFontSize,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    final isConsumed = content.status == ContentStatus.consumed;
    final isVideo = content.contentType == ContentType.youtube || content.contentType == ContentType.video;

    final hasBeenRead = isConsumed || content.readingProgress > 0;
    return Opacity(
      opacity: hasBeenRead ? 0.6 : 1.0,
      child: Stack(
        fit: expandContent ? StackFit.expand : StackFit.loose,
        children: [
          FacteurCard(
            // onTap/onLongPress removed from FacteurCard to avoid gesture
            // arena competition with footer action buttons (Save, "!" etc.).
            // Tap/long-press are handled directly on the image+body area below.
            backgroundColor: backgroundColor,
            boxShadow: boxShadow,
            padding: EdgeInsets.zero,
            borderRadius: FacteurRadius.small,
            child: Column(
              mainAxisSize: expandContent ? MainAxisSize.max : MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tappable area: image + body (isolated from footer buttons)
                GestureDetector(
                  onTap: onTap,
                  onLongPressStart: onLongPressStart,
                  onLongPressMoveUpdate: onLongPressMoveUpdate,
                  onLongPressEnd: onLongPressEnd,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Red accent line for video cards
                      if (isVideo)
                        Container(
                          height: 3,
                          color: const Color(0xFFFF0000),
                        ),

                      // 1. Image (Header)
                      FacteurThumbnail(
                        imageUrl: content.thumbnailUrl,
                        borderRadius: isVideo
                            ? BorderRadius.zero
                            : const BorderRadius.vertical(
                                top: Radius.circular(FacteurRadius.small)),
                        onError: onImageError,
                        overlay: isVideo ? const VideoPlayOverlay() : null,
                        durationLabel: isVideo && content.durationSeconds != null
                            ? _formatDuration(content.durationSeconds!)
                            : null,
                        isVideo: isVideo,
                      ),

                      // 2. Body (Title + Meta)
                      _buildBody(context, colors, textTheme),
                    ],
                  ),
                ),

                // 3. Footer (Source + Actions) — outside tap area
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
                            // Source Logo + Name (tappable for source detail — Epic 12)
                            Flexible(
                            child: GestureDetector(
                              onTap: onSourceTap,
                              behavior: HitTestBehavior.opaque,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Color.lerp(colors.backgroundSecondary, Colors.black, 0.003)!,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
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
                                              _buildSourcePlaceholder(colors),
                                        ),
                                      ),
                                      const SizedBox(width: FacteurSpacing.space2),
                                    ] else ...[
                                      _buildSourcePlaceholder(colors),
                                      const SizedBox(width: FacteurSpacing.space2),
                                    ],
                                    Flexible(
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
                                  ],
                                ),
                              ),
                            ),
                            ),

                            // Source suivie badge OR discovery follow CTA
                            if (isFollowedSource) ...[
                              const SizedBox(width: 4),
                              Icon(
                                PhosphorIcons.star(PhosphorIconsStyle.fill),
                                size: 12,
                                color: colors.textSecondary,
                              ),
                            ] else if (hasActiveFilter && onFollowSource != null) ...[
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: onFollowSource,
                                behavior: HitTestBehavior.opaque,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Color.lerp(colors.backgroundSecondary,
                                        Colors.black, 0.008),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Suivre',
                                        style: textTheme.labelSmall?.copyWith(
                                          color: colors.textTertiary,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      Icon(
                                        PhosphorIcons.plus(),
                                        size: 12,
                                        color: colors.textTertiary,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],

                            // Récence
                            const SizedBox(width: FacteurSpacing.space2),
                            Icon(
                              PhosphorIcons.clock(),
                              size: 12,
                              color: colors.textSecondary,
                            ),
                            const SizedBox(width: 3),
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

                            // Paywall badge (green "Abonné" if subscribed, yellow "Payant" otherwise)
                            if (content.isPaid) ...[
                              const SizedBox(width: FacteurSpacing.space2),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isSourceSubscribed
                                      ? colors.success.withValues(alpha: 0.15)
                                      : colors.warning.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isSourceSubscribed
                                          ? PhosphorIcons.crown(
                                              PhosphorIconsStyle.fill)
                                          : PhosphorIcons.lock(
                                              PhosphorIconsStyle.fill),
                                      size: 10,
                                      color: isSourceSubscribed
                                          ? colors.success
                                          : colors.warning,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      isSourceSubscribed
                                          ? 'Abonné'
                                          : 'Payant',
                                      style: TextStyle(
                                        color: isSourceSubscribed
                                            ? colors.success
                                            : colors.warning,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            // Editorial badge (digest only) — truncates before source name
                            if (editorialBadgeLabel != null) ...[
                              const SizedBox(width: FacteurSpacing.space2),
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color:
                                        colors.textSecondary.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: colors.textTertiary.withValues(alpha: 0.20),
                                      width: 0.5,
                                    ),
                                  ),
                                  child: Text(
                                    editorialBadgeLabel!,
                                    style: TextStyle(
                                      color: colors.textSecondary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      // Actions (Like, Save, NotInterested, Personalize)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Save button (tap = save/unsave, long press = collection picker)
                          if (onSave != null)
                            GestureDetector(
                              onTap: onSave,
                              onLongPress: onSaveLongPress,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                child: Icon(
                                  isSaved
                                      ? PhosphorIcons.bookmarkSimple(
                                          PhosphorIconsStyle.fill)
                                      : PhosphorIcons.bookmarkSimple(),
                                  size: 20,
                                  color: isSaved
                                      ? colors.primary
                                      : colors.textSecondary,
                                ),
                              ),
                            ),

                          // "Pas serein" report button (visible only in serene mode)
                          if (isSerene && onReportNotSerene != null)
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: onReportNotSerene,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                child: Icon(
                                  PhosphorIcons.shieldWarning(),
                                  size: 20,
                                  color: colors.warning,
                                ),
                              ),
                            ),

                          // Topic chip (replaces NotInterested when provided)
                          if (topicChipWidget != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: topicChipWidget!,
                            )
                          else if (onNotInterested != null)
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

                        ],
                      ),
                    ],
                  ),
                ),

                // Cluster chip (below footer)
                if (clusterChipWidget != null) clusterChipWidget!,
              ],
            ),
          ),
          if (content.hasNote)
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(10),
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
                      PhosphorIcons.pencilLine(PhosphorIconsStyle.fill),
                      size: 11,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 3),
                    const Text(
                      'Article annoté',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (isConsumed || content.readingProgress > 0)
            Positioned(
              top: 12,
              right: 12,
              child: ReadingBadge(content: content),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(
      BuildContext context, FacteurColors colors, TextTheme textTheme) {
    final hasDescription =
        content.description != null && content.description!.isNotEmpty;
    final showDescription = alwaysShowDescription
        ? hasDescription
        : expandContent
            ? hasDescription
            : ((content.thumbnailUrl == null ||
                    content.thumbnailUrl!.isEmpty) &&
                hasDescription);

    final bodyContent = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FacteurSpacing.space3,
        vertical: FacteurSpacing.space3,
      ),
      child: Column(
        mainAxisSize: expandContent ? MainAxisSize.max : MainAxisSize.min,
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
            maxLines: expandContent ? null : 3,
            overflow: expandContent ? null : TextOverflow.ellipsis,
          ),
          if (showDescription) ...[
            const SizedBox(height: FacteurSpacing.space2),
            Text(
              stripHtml(content.description!),
              style: textTheme.bodySmall?.copyWith(
                color: colors.textSecondary.withValues(alpha: 0.85),
                height: 1.3,
                fontSize: descriptionFontSize,
              ),
              maxLines: expandContent ? 8 : alwaysShowDescription ? 4 : 2,
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
    );

    if (expandContent) {
      return Expanded(child: bodyContent);
    }
    return bodyContent;
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
