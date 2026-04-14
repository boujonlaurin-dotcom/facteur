import 'package:flutter/material.dart';
import '../../../config/theme.dart';
import '../../feed/models/content_model.dart';
import '../../custom_topics/widgets/topic_chip.dart';
import '../../feed/widgets/feed_card.dart';
import '../../sources/models/source_model.dart';
import '../models/digest_models.dart';
import 'editorial_badge.dart';
import 'markdown_text.dart';

/// Editorial wrapper for the pépite article.
/// Displays a mini-editorial text above a FeedCard.
class PepiteBlock extends StatelessWidget {
  final PepiteResponse pepite;
  final void Function(DigestItem) onTap;
  final void Function(DigestItem)? onLike;
  final void Function(DigestItem)? onSave;
  final void Function(DigestItem)? onNotInterested;
  final void Function(DigestItem)? onReportNotSerene;
  final void Function(String sourceId)? onSourceTap;
  final bool isSerene;

  const PepiteBlock({
    super.key,
    required this.pepite,
    required this.onTap,
    this.onLike,
    this.onSave,
    this.onNotInterested,
    this.onReportNotSerene,
    this.onSourceTap,
    this.isSerene = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final item = _toDigestItem();

    final badgeChip = EditorialBadge.chip(pepite.badge, context: context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.08)
            : Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colors.border.withOpacity(isDark ? 0.22 : 0.16),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
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
                if (pepite.miniEditorial.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: MarkdownText(
                      text: pepite.miniEditorial,
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

          // Pépite card
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
            child: FeedCard(
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
              content: _convertToContent(item),
              descriptionFontSize: 15,
              onTap: () => onTap(item),
              onSourceTap: onSourceTap != null && pepite.source?.id != null
                  ? () => onSourceTap!(pepite.source!.id!)
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
              isSerene: isSerene,
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
      contentId: pepite.contentId,
      title: pepite.title,
      url: pepite.url,
      thumbnailUrl: pepite.thumbnailUrl,
      publishedAt: pepite.publishedAt,
      source: pepite.source,
      badge: pepite.badge,
      isRead: pepite.isRead,
      isSaved: pepite.isSaved,
      isLiked: pepite.isLiked,
      isDismissed: pepite.isDismissed,
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
