import 'package:flutter/material.dart';
import '../../../config/theme.dart';
import '../../feed/models/content_model.dart';
import '../../custom_topics/widgets/topic_chip.dart';
import '../../feed/widgets/feed_card.dart';
import '../../sources/models/source_model.dart';
import '../models/digest_models.dart';
import 'article_thumbs_feedback.dart';
import 'editorial_badge.dart';

/// Editorial wrapper for the coup de cœur article.
/// Displays a FeedCard with a save count label.
class CoupDeCoeurBlock extends StatelessWidget {
  final CoupDeCoeurResponse coupDeCoeur;
  final void Function(DigestItem) onTap;
  final void Function(DigestItem)? onLike;
  final void Function(DigestItem)? onSave;
  final void Function(DigestItem)? onNotInterested;
  final void Function(DigestItem)? onReportNotSerene;
  final void Function(String sourceId)? onSourceTap;
  final bool isSerene;

  const CoupDeCoeurBlock({
    super.key,
    required this.coupDeCoeur,
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
    final item = _toDigestItem();

    final badgeChip = EditorialBadge.chip(coupDeCoeur.badge, context: context);

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Editorial badge chip above
        if (badgeChip != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
            child: badgeChip,
          ),

        // Intro text before card
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 4, bottom: 10),
          child: Text(
            _introText(),
            style: TextStyle(
              fontStyle: FontStyle.italic,
              fontSize: 15,
              height: 1.5,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.8)
                  : colors.textSecondary,
            ),
          ),
        ),

        // Coup de cœur card
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: FeedCard(
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
            content: _convertToContent(item),
            descriptionFontSize: 15,
            onTap: () => onTap(item),
            onSourceTap: onSourceTap != null && coupDeCoeur.source?.id != null
                ? () => onSourceTap!(coupDeCoeur.source!.id!)
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

        // Article feedback thumbs
        ArticleThumbsFeedback(contentId: coupDeCoeur.contentId),
      ],
    );
  }

  String _introText() {
    if (coupDeCoeur.saveCount > 0) {
      return 'L\u2019article le plus gardé hier par les lecteurs de Facteur.';
    }
    return 'L\u2019article le plus apprécié hier par la communauté Facteur.';
  }

  DigestItem _toDigestItem() {
    return DigestItem(
      contentId: coupDeCoeur.contentId,
      title: coupDeCoeur.title,
      url: coupDeCoeur.url,
      thumbnailUrl: coupDeCoeur.thumbnailUrl,
      publishedAt: coupDeCoeur.publishedAt,
      source: coupDeCoeur.source,
      badge: coupDeCoeur.badge,
      isRead: coupDeCoeur.isRead,
      isSaved: coupDeCoeur.isSaved,
      isLiked: coupDeCoeur.isLiked,
      isDismissed: coupDeCoeur.isDismissed,
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
