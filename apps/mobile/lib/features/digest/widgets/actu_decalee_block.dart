import 'package:flutter/material.dart';
import '../../../config/theme.dart';
import '../../feed/models/content_model.dart';
import '../../custom_topics/widgets/topic_chip.dart';
import '../../feed/widgets/feed_card.dart';
import '../../sources/models/source_model.dart';
import '../models/digest_models.dart';
import 'editorial_badge.dart';
import 'markdown_text.dart';

/// Editorial wrapper for the "actu décalée" article (serein mode only).
/// Displays a mini-editorial text above a FeedCard, same pattern as PepiteBlock.
class ActuDecaleeBlock extends StatelessWidget {
  final PepiteResponse actuDecalee;
  final void Function(DigestItem) onTap;
  final void Function(DigestItem)? onLike;
  final void Function(DigestItem)? onSave;
  final void Function(DigestItem)? onNotInterested;
  final void Function(DigestItem)? onReportNotSerene;
  final void Function(String sourceId)? onSourceTap;

  const ActuDecaleeBlock({
    super.key,
    required this.actuDecalee,
    required this.onTap,
    this.onLike,
    this.onSave,
    this.onNotInterested,
    this.onReportNotSerene,
    this.onSourceTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final item = _toDigestItem();

    final badgeChip = EditorialBadge.chip(actuDecalee.badge, context: context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.05)
            : Colors.black.withOpacity(0.025),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colors.border.withOpacity(isDark ? 0.15 : 0.10),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Badge + mini-editorial header area
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (badgeChip != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: badgeChip,
                  ),
                if (actuDecalee.miniEditorial.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: MarkdownText(
                      text: actuDecalee.miniEditorial,
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        fontSize: 15,
                        height: 1.5,
                        color: isDark
                            ? Colors.white.withOpacity(0.8)
                            : colors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Actu décalée card
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
            child: FeedCard(
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
              content: _convertToContent(item),
              descriptionFontSize: 15,
              onTap: () => onTap(item),
              onSourceTap: onSourceTap != null && actuDecalee.source?.id != null
                  ? () => onSourceTap!(actuDecalee.source!.id!)
                  : null,
              onSourceLongPress: () => TopicChip.showArticleSheet(
                  context, _convertToContent(item),
                  initialSection: ArticleSheetSection.source),
              onLike: onLike != null ? () => onLike!(item) : null,
              isLiked: item.isLiked,
              onSave: onSave != null ? () => onSave!(item) : null,
              isSaved: item.isSaved,
              onNotInterested:
                  onNotInterested != null ? () => onNotInterested!(item) : null,
              isSerene: true,
              onReportNotSerene:
                  onReportNotSerene != null ? () => onReportNotSerene!(item) : null,
              isFollowedSource: item.isFollowedSource,
              editorialBadgeLabel: null,
            ),
          ),
        ],
      ),
    );
  }

  DigestItem _toDigestItem() {
    return DigestItem(
      contentId: actuDecalee.contentId,
      title: actuDecalee.title,
      url: actuDecalee.url,
      thumbnailUrl: actuDecalee.thumbnailUrl,
      publishedAt: actuDecalee.publishedAt,
      source: actuDecalee.source,
      badge: actuDecalee.badge,
      isRead: actuDecalee.isRead,
      isSaved: actuDecalee.isSaved,
      isLiked: actuDecalee.isLiked,
      isDismissed: actuDecalee.isDismissed,
    );
  }

  Content _convertToContent(DigestItem item) {
    return Content(
      id: item.contentId,
      title: item.title,
      url: item.url,
      thumbnailUrl: item.thumbnailUrl,
      description: item.description,
      contentType: item.contentType,
      durationSeconds: item.durationSeconds,
      publishedAt: item.publishedAt ?? DateTime.now(),
      source: Source(
        id: item.source?.id ?? item.contentId,
        name: item.source?.name ?? 'Source inconnue',
        type: _mapSourceType(item.contentType),
        logoUrl: item.source?.logoUrl,
        theme: item.source?.theme,
      ),
      isLiked: item.isLiked,
      isSaved: item.isSaved,
    );
  }

  SourceType _mapSourceType(ContentType type) {
    switch (type) {
      case ContentType.video:
        return SourceType.video;
      case ContentType.audio:
        return SourceType.podcast;
      case ContentType.youtube:
        return SourceType.youtube;
      default:
        return SourceType.article;
    }
  }
}
