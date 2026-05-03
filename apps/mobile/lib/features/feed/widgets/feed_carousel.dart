import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../../config/theme.dart';
import '../../../widgets/design/facteur_thumbnail.dart';
import '../../digest/widgets/editorial_badge.dart';
import '../models/content_model.dart';
import '../utils/article_title_layout.dart';
import 'feed_card.dart';

/// Horizontal carousel intercalated in the feed.
///
/// Displays 3-5 articles as a PageView (viewportFraction 0.88) with
/// contextual badges, animated page indicator dots, and a simple header.
/// Based on the TopicSection pattern from the Digest.
class FeedCarousel extends StatefulWidget {
  final FeedCarouselData data;
  final void Function(Content) onArticleTap;
  final void Function(String sourceId)? onSourceTap;

  // T1: Full card feature parity callbacks
  final void Function(Content, LongPressStartDetails)? onLongPressStart;
  final void Function(LongPressMoveUpdateDetails)? onLongPressMoveUpdate;
  final void Function(LongPressEndDetails)? onLongPressEnd;
  final void Function(Content)? onSave;
  final void Function(Content)? onSaveLongPress;
  final void Function(Content)? onLike;
  final void Function(Content)? onSourceLongPress;
  final Widget Function(Content)? topicChipBuilder;
  final void Function(Content)? onFollowSource;
  final Set<String>? subscribedSourceIds;
  final bool hasActiveFilter;
  final bool isSerene;
  final void Function(Content)? onReportNotSerene;

  /// Story 4.5b: appelé quand un item du carrousel apparaît pleinement à
  /// l'écran (≥ 90 % de viewport). Utilisé par le feed refresh viewport-aware.
  final void Function(String contentId)? onItemVisible;

  const FeedCarousel({
    super.key,
    required this.data,
    required this.onArticleTap,
    this.onSourceTap,
    this.onLongPressStart,
    this.onLongPressMoveUpdate,
    this.onLongPressEnd,
    this.onSave,
    this.onSaveLongPress,
    this.onLike,
    this.onSourceLongPress,
    this.topicChipBuilder,
    this.onFollowSource,
    this.subscribedSourceIds,
    this.hasActiveFilter = false,
    this.isSerene = false,
    this.onReportNotSerene,
    this.onItemVisible,
  });

  @override
  State<FeedCarousel> createState() => _FeedCarouselState();
}

class _FeedCarouselState extends State<FeedCarousel> {
  late final PageController _pageController;
  int _currentPage = 0;
  final Set<String> _collapsedImages = {};

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      viewportFraction: widget.data.items.length > 1 ? 0.88 : 1.0,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // Layout constants (matches TopicSection)
  static const double _footerHeight = 57.0;
  static const double _bodyPadding = 24.0;
  static const double _metaRowHeight = 20.0;
  static const double _spacer = 8.0;
  static const double _badgeHeight = 30.0; // Badge chip above card

  bool _imageWillRender(Content article) {
    final url = article.thumbnailUrl;
    return url != null &&
        url.isNotEmpty &&
        !FacteurThumbnail.failedUrls.contains(url) &&
        !_collapsedImages.contains(article.id);
  }

  void _onImageError(String contentId) {
    if (mounted && !_collapsedImages.contains(contentId)) {
      setState(() => _collapsedImages.add(contentId));
    }
  }

  double _estimateCardHeight(Content article, double cardWidth) {
    final hasImage = _imageWillRender(article);

    final titleLines = ArticleTitleLayout.estimateTitleLines(
      title: article.title,
      availableWidth: cardWidth - _bodyPadding,
      hasImage: hasImage,
    );
    final titleHeight = titleLines * ArticleTitleLayout.titleLineHeight;

    double bodyHeight = _bodyPadding + titleHeight + _spacer + _metaRowHeight;

    if (!hasImage) {
      final desc = article.description ?? '';
      if (desc.isNotEmpty) {
        final descMax = ArticleTitleLayout.descriptionMaxLinesForCarousel(
          estimatedTitleLines: titleLines,
          hasImage: false,
          hasDescription: true,
        );
        final descLines = ArticleTitleLayout.estimateDescriptionLines(
          description: desc,
          availableWidth: cardWidth - _bodyPadding,
          maxLines: descMax,
        );
        if (descLines > 0) {
          bodyHeight += _spacer + descLines * ArticleTitleLayout.descLineHeight;
        }
      }
    }

    final imageHeight = hasImage ? cardWidth / (16 / 9) : 0.0;
    return imageHeight + bodyHeight + _footerHeight + _badgeHeight;
  }

  double _computeHeight(double cardWidth) {
    double maxH = 0;
    for (final article in widget.data.items) {
      final h = _estimateCardHeight(article, cardWidth);
      if (h > maxH) maxH = h;
    }
    return maxH;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final data = widget.data;

    if (data.items.isEmpty) return const SizedBox.shrink();

    final isMulti = data.items.length > 1;

    final readCount = data.items
        .where((c) =>
            c.status == ContentStatus.consumed || c.readingProgress > 0)
        .length;
    final total = data.items.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  data.title,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (readCount > 0) ...[
                const SizedBox(width: 8),
                _buildCompletionBadge(context, readCount, total),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),

        // PageView
        if (isMulti)
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = constraints.maxWidth * 0.88;
              final computedHeight = _computeHeight(cardWidth);

              return AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                height: computedHeight,
                child: ClipRect(
                  child: _buildPageView(),
                ),
              );
            },
          )
        else
          _buildSingleCard(data.items.first, 0),

        // Page indicator dots
        if (isMulti) ...[
          const SizedBox(height: 2),
          _buildPageIndicator(colors, data.items.length),
        ],

        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildPageView() {
    return PageView.builder(
      controller: _pageController,
      onPageChanged: (index) => setState(() => _currentPage = index),
      itemCount: widget.data.items.length,
      itemBuilder: (context, index) {
        final article = widget.data.items[index];
        final imageVisible = _imageWillRender(article);

        // Get contextual badge for this item
        Widget? badgeChip;
        if (index < widget.data.badges.length) {
          badgeChip = EditorialBadge.carouselChip(
            widget.data.badges[index],
            context: context,
          );
        }

        // T5: Grey out reference_read articles
        final isReference = index < widget.data.badges.length &&
            widget.data.badges[index].code == 'reference_read';

        final card = FeedCard(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
          backgroundColor:
              isReference ? Colors.grey.withOpacity(0.1) : null,
          content: article,
          alwaysShowDescription: !imageVisible,
          descriptionFontSize: 15,
          titleMaxLines: 5,
          onImageError: () => _onImageError(article.id),
          onTap: () => widget.onArticleTap(article),
          // T1: Full card feature parity
          onLongPressStart: widget.onLongPressStart != null
              ? (details) => widget.onLongPressStart!(article, details)
              : null,
          onLongPressMoveUpdate: widget.onLongPressMoveUpdate,
          onLongPressEnd: widget.onLongPressEnd,
          onSave: widget.onSave != null ? () => widget.onSave!(article) : null,
          onSaveLongPress: widget.onSaveLongPress != null
              ? () => widget.onSaveLongPress!(article)
              : null,
          onLike: widget.onLike != null ? () => widget.onLike!(article) : null,
          onSourceTap: widget.onSourceTap != null
              ? () => widget.onSourceTap!(article.source.id)
              : null,
          onSourceLongPress: widget.onSourceLongPress != null
              ? () => widget.onSourceLongPress!(article)
              : null,
          topicChipWidget: widget.topicChipBuilder?.call(article),
          // DEADCODE (ClusterChip feature temporairement masquée)
          // clusterChipWidget: const SizedBox.shrink(),
          isFollowedSource: article.isFollowedSource,
          isSaved: article.isSaved,
          isLiked: article.isLiked,
          isSourceSubscribed:
              widget.subscribedSourceIds?.contains(article.source.id) ?? false,
          hasActiveFilter: widget.hasActiveFilter,
          onFollowSource:
              widget.onFollowSource != null && !article.isFollowedSource
                  ? () => widget.onFollowSource!(article)
                  : null,
          isSerene: widget.isSerene,
          onReportNotSerene: widget.onReportNotSerene != null
              ? () => widget.onReportNotSerene!(article)
              : null,
        );

        final wrappedCard =
            isReference ? Opacity(opacity: 0.65, child: card) : card;

        return VisibilityDetector(
          key: ValueKey('carousel_vis_${article.id}'),
          onVisibilityChanged: (info) {
            if (info.visibleFraction >= 0.9) {
              widget.onItemVisible?.call(article.id);
            }
          },
          child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Align(
            alignment: Alignment.topCenter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (badgeChip != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: badgeChip,
                  ),
                wrappedCard,
              ],
            ),
          ),
          ),
        );
      },
    );
  }

  Widget _buildSingleCard(Content article, int badgeIndex) {
    final imageVisible = _imageWillRender(article);

    Widget? badgeChip;
    if (badgeIndex < widget.data.badges.length) {
      badgeChip = EditorialBadge.carouselChip(
        widget.data.badges[badgeIndex],
        context: context,
      );
    }

    // T5: Grey out reference_read articles
    final isReference = badgeIndex < widget.data.badges.length &&
        widget.data.badges[badgeIndex].code == 'reference_read';

    final card = FeedCard(
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
      backgroundColor: isReference ? Colors.grey.withOpacity(0.1) : null,
      content: article,
      alwaysShowDescription: !imageVisible,
      descriptionFontSize: 15,
      titleMaxLines: 5,
      onImageError: () => _onImageError(article.id),
      onTap: () => widget.onArticleTap(article),
      // T1: Full card feature parity
      onLongPressStart: widget.onLongPressStart != null
          ? (details) => widget.onLongPressStart!(article, details)
          : null,
      onLongPressMoveUpdate: widget.onLongPressMoveUpdate,
      onLongPressEnd: widget.onLongPressEnd,
      onSave: widget.onSave != null ? () => widget.onSave!(article) : null,
      onSaveLongPress: widget.onSaveLongPress != null
          ? () => widget.onSaveLongPress!(article)
          : null,
      onLike: widget.onLike != null ? () => widget.onLike!(article) : null,
      onSourceTap: widget.onSourceTap != null
          ? () => widget.onSourceTap!(article.source.id)
          : null,
      onSourceLongPress: widget.onSourceLongPress != null
          ? () => widget.onSourceLongPress!(article)
          : null,
      topicChipWidget: widget.topicChipBuilder?.call(article),
      // DEADCODE (ClusterChip feature temporairement masquée)
      // clusterChipWidget: const SizedBox.shrink(),
      isFollowedSource: article.isFollowedSource,
      isSaved: article.isSaved,
      isLiked: article.isLiked,
      isSourceSubscribed:
          widget.subscribedSourceIds?.contains(article.source.id) ?? false,
      hasActiveFilter: widget.hasActiveFilter,
      onFollowSource: widget.onFollowSource != null && !article.isFollowedSource
          ? () => widget.onFollowSource!(article)
          : null,
      isSerene: widget.isSerene,
      onReportNotSerene: widget.onReportNotSerene != null
          ? () => widget.onReportNotSerene!(article)
          : null,
    );

    final wrappedCard =
        isReference ? Opacity(opacity: 0.65, child: card) : card;

    return VisibilityDetector(
      key: ValueKey('carousel_vis_${article.id}'),
      onVisibilityChanged: (info) {
        if (info.visibleFraction >= 0.9) {
          widget.onItemVisible?.call(article.id);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (badgeChip != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: badgeChip,
              ),
            wrappedCard,
          ],
        ),
      ),
    );
  }

  Widget _buildCompletionBadge(BuildContext context, int readCount, int total) {
    final colors = context.facteurColors;
    final allRead = readCount == total;
    final bgColor =
        allRead ? colors.success : colors.success.withOpacity(0.12);
    final fgColor = allRead ? Colors.white : colors.success;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (allRead) ...[
            Icon(PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
                size: 10, color: fgColor),
            const SizedBox(width: 3),
          ],
          Text(
            '$readCount/$total',
            style: TextStyle(
              color: fgColor,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageIndicator(FacteurColors colors, int count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final isActive = index == _currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: isActive ? 24 : 10,
          height: 10,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: isActive
                ? colors.primary
                : colors.textTertiary.withOpacity(0.3),
            borderRadius: BorderRadius.circular(5),
          ),
        );
      }),
    );
  }
}
