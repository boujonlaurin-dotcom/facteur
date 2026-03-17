import 'package:flutter/material.dart';
import '../../../config/theme.dart';
import '../../feed/models/content_model.dart';
import '../../feed/widgets/feed_card.dart';
import '../../sources/models/source_model.dart';
import '../models/digest_models.dart';

/// Editorial wrapper for the pépite article.
/// Displays a mini-editorial text above a FeedCard.
class PepiteBlock extends StatelessWidget {
  final PepiteResponse pepite;
  final void Function(DigestItem) onTap;
  final void Function(DigestItem)? onLike;
  final void Function(DigestItem)? onSave;
  final void Function(DigestItem)? onNotInterested;
  final bool isSerene;

  const PepiteBlock({
    super.key,
    required this.pepite,
    required this.onTap,
    this.onLike,
    this.onSave,
    this.onNotInterested,
    this.isSerene = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final item = _toDigestItem();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mini-editorial text
        if (pepite.miniEditorial.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(
              left: 4,
              right: 4,
              bottom: 10,
            ),
            child: Text(
              pepite.miniEditorial,
              style: TextStyle(
                fontStyle: FontStyle.italic,
                fontSize: 14,
                height: 1.5,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.8)
                    : colors.textSecondary,
              ),
            ),
          ),

        // Pépite card
        FeedCard(
          boxShadow: const [],
          content: _convertToContent(item),
          onTap: () => onTap(item),
          onLike: onLike != null ? () => onLike!(item) : null,
          isLiked: item.isLiked,
          onSave: onSave != null ? () => onSave!(item) : null,
          isSaved: item.isSaved,
          onNotInterested:
              onNotInterested != null ? () => onNotInterested!(item) : null,
          isFollowedSource: item.isFollowedSource,
        ),
      ],
    );
  }

  DigestItem _toDigestItem() {
    return DigestItem(
      contentId: pepite.contentId,
      title: pepite.title,
      url: pepite.url,
      thumbnailUrl: pepite.thumbnailUrl,
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
