import 'package:flutter/material.dart';
import '../../../config/theme.dart';
import '../../feed/models/content_model.dart';
import '../../feed/widgets/feed_card.dart';
import '../../sources/models/source_model.dart';
import '../models/digest_models.dart';
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Coup de cœur card
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: FeedCard(
            boxShadow: const [],
            content: _convertToContent(item),
            descriptionFontSize: 15,
            onTap: () => onTap(item),
            onSourceTap: onSourceTap != null && coupDeCoeur.source?.id != null
                ? () => onSourceTap!(coupDeCoeur.source!.id!)
                : null,
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
            editorialBadgeLabel: EditorialBadge.labelFor(coupDeCoeur.badge),
          ),
        ),

        // Save count label
        if (coupDeCoeur.saveCount > 0)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 6),
            child: Text(
              'Gardé par ${coupDeCoeur.saveCount} lecteurs',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w400,
                fontStyle: FontStyle.italic,
                color: colors.textSecondary,
              ),
            ),
          ),
      ],
    );
  }

  DigestItem _toDigestItem() {
    return DigestItem(
      contentId: coupDeCoeur.contentId,
      title: coupDeCoeur.title,
      url: coupDeCoeur.url,
      thumbnailUrl: coupDeCoeur.thumbnailUrl,
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
