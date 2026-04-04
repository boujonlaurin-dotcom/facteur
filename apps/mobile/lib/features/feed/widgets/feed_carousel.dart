import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../../../widgets/design/facteur_thumbnail.dart';
import '../../digest/widgets/editorial_badge.dart';
import '../models/content_model.dart';
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

  const FeedCarousel({
    super.key,
    required this.data,
    required this.onArticleTap,
    this.onSourceTap,
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

    final charsPerLine = (cardWidth - _bodyPadding) / 10;
    final titleLines =
        (article.title.length / charsPerLine).ceil().clamp(1, 3);
    final titleHeight = titleLines * 20.0 * 1.2;

    double bodyHeight = _bodyPadding + titleHeight + _spacer + _metaRowHeight;

    if (!hasImage) {
      final desc = article.description ?? '';
      if (desc.isNotEmpty) {
        final descCharsPerLine = (cardWidth - _bodyPadding) / 8;
        final descLines =
            (desc.length / descCharsPerLine).ceil().clamp(1, 4);
        final descHeight = descLines * 15.0 * 1.3;
        bodyHeight += _spacer + descHeight;
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                data.emoji,
                style: const TextStyle(fontSize: 20),
              ),
              const SizedBox(width: 8),
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

        final card = FeedCard(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
          content: article,
          alwaysShowDescription: !imageVisible,
          descriptionFontSize: 15,
          onImageError: () => _onImageError(article.id),
          onTap: () => widget.onArticleTap(article),
          onSourceTap: widget.onSourceTap != null
              ? () => widget.onSourceTap!(article.source.id)
              : null,
          isFollowedSource: article.isFollowedSource,
          isSaved: article.isSaved,
          isLiked: article.isLiked,
        );

        return Padding(
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
                card,
              ],
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

    return Padding(
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
          FeedCard(
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
            content: article,
            alwaysShowDescription: !imageVisible,
            descriptionFontSize: 15,
            onImageError: () => _onImageError(article.id),
            onTap: () => widget.onArticleTap(article),
            onSourceTap: widget.onSourceTap != null
                ? () => widget.onSourceTap!(article.source.id)
                : null,
            isFollowedSource: article.isFollowedSource,
            isSaved: article.isSaved,
            isLiked: article.isLiked,
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
                : colors.textTertiary.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(5),
          ),
        );
      }),
    );
  }
}
