import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../feed/models/content_model.dart';
import '../../feed/widgets/feed_card.dart';
import '../../sources/models/source_model.dart';
import '../models/digest_models.dart';

/// A single topic section in the digest topics layout.
///
/// Flat section (no card container) with:
/// 1. Header: rank + reason + topic label + badges
/// 2. Horizontal PageView of article cards
/// 3. Page indicator dots for multi-article topics
class TopicSection extends StatefulWidget {
  final DigestTopic topic;
  final void Function(DigestItem) onArticleTap;
  final void Function(DigestItem)? onLike;
  final void Function(DigestItem)? onSave;
  final void Function(DigestItem)? onNotInterested;

  const TopicSection({
    super.key,
    required this.topic,
    required this.onArticleTap,
    this.onLike,
    this.onSave,
    this.onNotInterested,
  });

  @override
  State<TopicSection> createState() => _TopicSectionState();
}

class _TopicSectionState extends State<TopicSection> {
  late final PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      viewportFraction:
          widget.topic.articles.length > 1 ? 0.88 : 1.0,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Estimated body + footer height for FeedCard WITH image.
  /// Body: padding (24) + title 3×24px (72) + SizedBox (8) + meta row (20)
  /// Footer: border (1) + padding (8) + row with button padding (32)
  /// Buffer for box shadow + rounding = 7
  static const double _bodyFooterHeight = 172.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topic = widget.topic;
    final isMulti = topic.articles.length > 1;

    return AnimatedOpacity(
      opacity: topic.isCovered ? 0.7 : 1.0,
      duration: const Duration(milliseconds: 300),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header (flat, no card wrapper)
          _buildHeader(context, colors, isDark, topic),
          const SizedBox(height: 8),

          // Article card(s)
          if (isMulti)
            // Multi-article: PageView needs a fixed height
            LayoutBuilder(
              builder: (context, constraints) {
                final cardWidth = constraints.maxWidth * 0.88;
                final hasAnyImage = topic.articles.any((a) =>
                    a.thumbnailUrl != null && a.thumbnailUrl!.isNotEmpty);
                final imageHeight =
                    hasAnyImage ? cardWidth / (16 / 9) : 0.0;
                final computedHeight = imageHeight + _bodyFooterHeight;

                return SizedBox(
                  height: computedHeight,
                  child: _buildPageView(topic),
                );
              },
            )
          else
            // Singleton: no PageView, let the card size itself naturally
            _buildSingleArticle(topic.articles.first),

          // Page indicator dots (only for multi-article)
          if (isMulti) ...[
            const SizedBox(height: 8),
            _buildPageIndicator(colors, topic.articles.length),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    FacteurColors colors,
    bool isDark,
    DigestTopic topic,
  ) {
    final labelColor = isDark
        ? const Color(0x80FFFFFF)
        : const Color(0x802C1E10);
    final dotColor = isDark
        ? const Color(0x33FFFFFF)
        : const Color(0x332C1E10);
    final isSingleton = topic.articles.length == 1;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: "N°1" + dot + REASON + covered check (always shown)
          Row(
            children: [
              Text(
                'N\u00B0${topic.rank}',
                style: TextStyle(
                  color: colors.primary.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _simplifyReason(topic.reason),
                  style: TextStyle(
                    color: labelColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                    letterSpacing: 0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (topic.isCovered)
                Icon(
                  PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
                  size: 16,
                  color: colors.success,
                ),
            ],
          ),

          // Row 2: Topic label — skip for singletons (card title is the same)
          if (!isSingleton) ...[
            const SizedBox(height: 4),
            Text(
              topic.label,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: isDark ? Colors.white : const Color(0xFF2C1E10),
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          // Row 3: Badges — skip for singletons
          if (!isSingleton && (topic.isTrending || topic.isUne)) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                if (topic.isTrending)
                  _buildBadge(
                    colors,
                    isDark,
                    icon: PhosphorIcons.trendUp(PhosphorIconsStyle.bold),
                    label: 'Couvert par ${topic.sourceCount} sources',
                  ),
                if (topic.isUne)
                  _buildBadge(
                    colors,
                    isDark,
                    icon: PhosphorIcons.newspaper(PhosphorIconsStyle.bold),
                    label: 'A la une',
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBadge(
    FacteurColors colors,
    bool isDark, {
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: isDark ? 0.15 : 0.10),
        borderRadius: BorderRadius.circular(FacteurRadius.small),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: colors.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: colors.primary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSingleArticle(DigestItem article) {
    return FeedCard(
      content: _convertToContent(article),
      onTap: () => widget.onArticleTap(article),
      onLike: widget.onLike != null ? () => widget.onLike!(article) : null,
      isLiked: article.isLiked,
      onSave: widget.onSave != null ? () => widget.onSave!(article) : null,
      isSaved: article.isSaved,
      onNotInterested: widget.onNotInterested != null
          ? () => widget.onNotInterested!(article)
          : null,
      isFollowedSource: article.isFollowedSource,
    );
  }

  Widget _buildPageView(DigestTopic topic) {
    return PageView.builder(
      controller: _pageController,
      onPageChanged: (index) => setState(() => _currentPage = index),
      itemCount: topic.articles.length,
      itemBuilder: (context, index) {
        final article = topic.articles[index];
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FeedCard(
            content: _convertToContent(article),
            onTap: () => widget.onArticleTap(article),
            onLike:
                widget.onLike != null ? () => widget.onLike!(article) : null,
            isLiked: article.isLiked,
            onSave:
                widget.onSave != null ? () => widget.onSave!(article) : null,
            isSaved: article.isSaved,
            onNotInterested: widget.onNotInterested != null
                ? () => widget.onNotInterested!(article)
                : null,
            isFollowedSource: article.isFollowedSource,
          ),
        );
      },
    );
  }

  Widget _buildPageIndicator(FacteurColors colors, int count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final isActive = index == _currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: isActive ? 16 : 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: isActive
                ? colors.primary
                : colors.textTertiary.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }

  /// Converts DigestItem to Content for FeedCard compatibility
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

  /// Clean up reason strings for display.
  static String _simplifyReason(String reason) {
    var r = reason;
    r = r.replaceAll(RegExp(r'\s*\(\+\d+\s*pts?\)'), '');
    if (r.contains(':') && !r.startsWith('Th\u00e8me')) {
      r = r.split(':').first.trim();
    }
    r = r.replaceAll(RegExp(r'\s+depuis\s+.*', caseSensitive: false), '');
    return r.trim().toUpperCase();
  }
}
