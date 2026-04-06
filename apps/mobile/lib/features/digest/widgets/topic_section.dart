import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../config/theme.dart';
import '../../../widgets/article_preview_modal.dart';
import '../../../widgets/design/facteur_thumbnail.dart';
import '../../custom_topics/widgets/topic_chip.dart';
import '../../feed/models/content_model.dart';
import '../../feed/providers/feed_provider.dart';
import '../../feed/widgets/dismiss_banner.dart';
import '../../feed/widgets/feed_card.dart';
import '../../feed/widgets/keyword_overflow_chip.dart';
import '../../feed/widgets/perspectives_bottom_sheet.dart';
import '../../saved/widgets/collection_picker_sheet.dart';
import '../../sources/models/source_model.dart';
import '../models/digest_models.dart';
import 'article_thumbs_feedback.dart';
import 'divergence_analysis_block.dart';
import 'editorial_badge.dart';
import 'pas_de_recul_block.dart';
import 'source_coverage_badge.dart';

/// A single topic section in the digest topics layout.
///
/// Flat section (no card container) with:
/// 1. Header: rank + reason + topic label + badges
/// 2. Horizontal PageView of article cards
/// 3. Page indicator dots for multi-article topics
///
/// In editorial mode, supports expand/collapse toggle:
/// - Compact (default): small image + title + badges + 1-line description
/// - Expanded: full FeedCard + divergence analysis + pas de recul
class TopicSection extends ConsumerStatefulWidget {
  final DigestTopic topic;
  final void Function(DigestItem) onArticleTap;
  final void Function(DigestItem)? onLike;
  final void Function(DigestItem)? onSave;
  final void Function(DigestItem)? onNotInterested;
  final void Function(DigestItem)? onReportNotSerene;
  final void Function(DigestItem)? onSwipeDismiss;
  final String? activeDismissalId;
  final VoidCallback? onDismissUndo;
  final VoidCallback? onDismissAutoResolve;
  final VoidCallback? onDismissMuteSource;
  final void Function(String topic)? onDismissMuteTopic;
  final void Function(String sourceId)? onSourceTap;
  final bool editorialMode;
  final bool isSerene;

  const TopicSection({
    super.key,
    required this.topic,
    required this.onArticleTap,
    this.onLike,
    this.onSave,
    this.onNotInterested,
    this.onReportNotSerene,
    this.onSwipeDismiss,
    this.activeDismissalId,
    this.onDismissUndo,
    this.onDismissAutoResolve,
    this.onDismissMuteSource,
    this.onDismissMuteTopic,
    this.onSourceTap,
    this.editorialMode = false,
    this.isSerene = false,
  });

  @override
  ConsumerState<TopicSection> createState() => _TopicSectionState();
}

class _TopicSectionState extends ConsumerState<TopicSection>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => widget.editorialMode;

  late final PageController _pageController;
  int _currentPage = 0;
  bool _isExpanded = false;

  /// Content IDs whose images failed to load (detected at runtime).
  final Set<String> _collapsedImages = {};

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      viewportFraction: widget.topic.articles.length > 1 ? 0.88 : 1.0,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Footer height: border (1) + padding (4×2) + icon row (~28) = ~37
  static const double _footerHeight = 57.0;

  /// Body padding top + bottom (FacteurSpacing.space3 × 2 = 24)
  static const double _bodyPadding = 24.0;

  /// Meta row: type icon + duration text
  static const double _metaRowHeight = 20.0;

  /// SizedBox spacers inside body (space2 = 8 each)
  static const double _spacer = 8.0;

  /// Badge chip above card (chip height + bottom padding)
  static const double _badgeHeight = 30.0;

  /// Returns true if this article's image is expected to render.
  bool _imageWillRender(DigestItem article) {
    final url = article.thumbnailUrl;
    return url != null &&
        url.isNotEmpty &&
        !FacteurThumbnail.failedUrls.contains(url) &&
        !_collapsedImages.contains(article.contentId);
  }

  /// Called by FeedCard when FacteurThumbnail reports an image error.
  void _onImageError(String contentId) {
    if (mounted && !_collapsedImages.contains(contentId)) {
      setState(() => _collapsedImages.add(contentId));
    }
  }

  /// Estimate a single card's height based on its content.
  double _estimateCardHeight(DigestItem article, double cardWidth) {
    final hasImage = _imageWillRender(article);

    // Title: fontSize 20, lineHeight 1.2, maxLines 3
    // Estimate line count from title length vs available width.
    // Average char width ≈ 10px at fontSize 20 → chars per line ≈ cardWidth / 10.
    final charsPerLine = (cardWidth - _bodyPadding) / 10;
    final titleLines =
        (article.title.length / charsPerLine).ceil().clamp(1, 3);
    final titleHeight = titleLines * 20.0 * 1.2;

    double bodyHeight = _bodyPadding + titleHeight + _spacer + _metaRowHeight;

    // Description only shown when no image (alwaysShowDescription: !imageVisible)
    if (!hasImage) {
      final desc = article.description ?? '';
      if (desc.isNotEmpty) {
        final descCharsPerLine = (cardWidth - _bodyPadding) / 8;
        final descLines =
            (desc.length / descCharsPerLine).ceil().clamp(1, 4);
        // descriptionFontSize: 15, lineHeight: 1.3
        final descHeight = descLines * 15.0 * 1.3;
        bodyHeight += _spacer + descHeight;
      }
    }

    final imageHeight = hasImage ? cardWidth / (16 / 9) : 0.0;
    // Badge chip above card + 8px safety margin for text estimation variance
    return imageHeight + bodyHeight + _footerHeight + _badgeHeight + 8.0;
  }

  /// Compute carousel height: max of all cards (adjacent cards peek at 0.88).
  double _computeHeight(List<DigestItem> articles, double cardWidth) {
    double maxH = 0;
    for (final article in articles) {
      final h = _estimateCardHeight(article, cardWidth);
      if (h > maxH) maxH = h;
    }
    return maxH;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = context.facteurColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topic = widget.topic;
    final isMulti = topic.articles.length > 1;

    // If no articles or all dismissed, hide the entire section
    if (topic.articles.isEmpty) {
      debugPrint('TopicSection: 0 articles for topic ${topic.label}');
      return const SizedBox.shrink();
    }
    final allDismissed = topic.articles.every((a) => a.isDismissed);
    if (allDismissed) return const SizedBox.shrink();

    // Editorial mode: toggle expand/collapse
    if (widget.editorialMode) {
      final actuArticles = topic.articles
          .where((a) => a.badge != 'pas_de_recul')
          .toList();
      if (actuArticles.isEmpty) return const SizedBox.shrink();
      final isActuMulti = actuArticles.length > 1;
      return AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_isExpanded)
              _buildHeader(context, colors, isDark, topic),
            if (!_isExpanded)
              const SizedBox(height: 8),
            if (_isExpanded)
              _buildExpandedEditorial(colors, isDark, topic, actuArticles, isActuMulti)
            else
              _buildCompactEditorialCard(colors, isDark, topic, actuArticles),
            ArticleThumbsFeedback(
              contentId: isActuMulti
                  ? actuArticles[_currentPage.clamp(0, actuArticles.length - 1)].contentId
                  : actuArticles.first.contentId,
            ),
          ],
        ),
      );
    }

    // Non-editorial mode: unchanged
    return AnimatedOpacity(
      opacity: topic.isCovered ? 0.7 : 1.0,
      duration: const Duration(milliseconds: 300),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context, colors, isDark, topic),
          const SizedBox(height: 8),

          // Article card(s)
          if (isMulti)
            // Multi-article: PageView with dynamic height
            LayoutBuilder(
              builder: (context, constraints) {
                final cardWidth = constraints.maxWidth * 0.88;
                final computedHeight =
                    _computeHeight(topic.articles, cardWidth);

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  height: computedHeight,
                  child: ClipRect(
                    child: _buildPageView(topic.articles),
                  ),
                );
              },
            )
          else if (!topic.articles.first.isDismissed)
            _buildSingleArticle(topic.articles.first),

          // Page indicator dots (only for multi-article)
          if (isMulti) ...[
            const SizedBox(height: 2),
            _buildPageIndicator(colors, topic.articles.length),
          ],

          // Article feedback thumbs (1 per topic group)
          ArticleThumbsFeedback(
            contentId: isMulti
                ? topic.articles[_currentPage].contentId
                : topic.articles.first.contentId,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Editorial mode: compact card (closed state)
  // ---------------------------------------------------------------------------

  Widget _buildCompactEditorialCard(
    FacteurColors colors,
    bool isDark,
    DigestTopic topic,
    List<DigestItem> actuArticles,
  ) {
    final safeIndex = _currentPage.clamp(0, actuArticles.length - 1);
    final article = actuArticles[safeIndex];
    final hasImage = _imageWillRender(article);
    final timeAgo = article.publishedAt != null
        ? timeago
            .format(article.publishedAt!, locale: 'fr_short')
            .replaceAll('il y a ', '')
        : null;

    final isHero = topic.isUne && hasImage;

    return GestureDetector(
      onTap: () => setState(() => _isExpanded = true),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: isHero
              ? Border(
                  left: BorderSide(width: 3, color: colors.primary),
                )
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: topic.isUne
            ? (hasImage
                ? _buildCompactHeroCard(
                    colors, isDark, article, topic, timeAgo)
                : _buildCompactHeroNoImage(
                    colors, isDark, article, topic, timeAgo))
            : (hasImage
                ? _buildCompactWithImage(
                    colors, isDark, article, topic, timeAgo)
                : _buildCompactWithoutImage(
                    colors, isDark, article, topic, timeAgo)),
      ),
    );
  }

  Widget _buildCompactWithImage(
    FacteurColors colors,
    bool isDark,
    DigestItem article,
    DigestTopic topic,
    String? timeAgo,
  ) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left: compact image (1:1 ratio, ~120px width)
          SizedBox(
            width: 120,
            child: FacteurThumbnail(
              imageUrl: article.thumbnailUrl,
              aspectRatio: 1.0,
              borderRadius: BorderRadius.zero,
              onError: () => _onImageError(article.contentId),
            ),
          ),
          // Right: text content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Title
                  Text(
                    article.title,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      height: 1.3,
                      color: isDark ? Colors.white : colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Footer: source logos · time · expand icon
                  _buildCompactFooter(colors, isDark, topic, timeAgo),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactWithoutImage(
    FacteurColors colors,
    bool isDark,
    DigestItem article,
    DigestTopic topic,
    String? timeAgo,
  ) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            article.title,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              height: 1.3,
              color: isDark ? Colors.white : colors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          _buildCompactFooter(colors, isDark, topic, timeAgo),
        ],
      ),
    );
  }

  Widget _buildCompactHeroCard(
    FacteurColors colors,
    bool isDark,
    DigestItem article,
    DigestTopic topic,
    String? timeAgo,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Full-width 16:9 image with gradient overlay + title
        Stack(
          alignment: Alignment.bottomLeft,
          children: [
            FacteurThumbnail(
              imageUrl: article.thumbnailUrl,
              aspectRatio: 16 / 9,
              borderRadius: BorderRadius.zero,
              onError: () => _onImageError(article.contentId),
            ),
            // Gradient overlay
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.7),
                    ],
                    stops: const [0.4, 1.0],
                  ),
                ),
              ),
            ),
            // Badge "À la Une" + title
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'À la Une',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    article.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      height: 1.3,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        // Footer: source logos + time + chevron
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: _buildCompactFooter(colors, isDark, topic, timeAgo),
        ),
      ],
    );
  }

  Widget _buildCompactHeroNoImage(
    FacteurColors colors,
    bool isDark,
    DigestItem article,
    DigestTopic topic,
    String? timeAgo,
  ) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EditorialBadge.chip('actu', context: context) ??
              const SizedBox.shrink(),
          const SizedBox(height: 8),
          Text(
            article.title,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              height: 1.3,
              color: isDark ? Colors.white : colors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          _buildCompactFooter(colors, isDark, topic, timeAgo),
        ],
      ),
    );
  }

  Widget _buildCompactBadgesRow(
    FacteurColors colors,
    bool isDark,
    DigestTopic topic,
  ) {
    final perspCount = topic.perspectiveCount;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        if (perspCount > 1)
          SourceCoverageBadge(
            perspectiveCount: perspCount,
            isTrending: topic.isTrending,
          ),
        if (topic.isUne)
          EditorialBadge.chip('actu', context: context) ?? const SizedBox.shrink(),
      ],
    );
  }

  Widget _buildCompactFooter(
    FacteurColors colors,
    bool isDark,
    DigestTopic topic,
    String? timeAgo,
  ) {
    final seen = <String>{};
    final logoSources = <KeywordOverflowSource>[];
    for (final a in topic.articles) {
      final s = a.source;
      if (s != null && s.id != null && seen.add(s.id!)) {
        logoSources.add(KeywordOverflowSource(
          sourceId: s.id!,
          sourceName: s.name,
          sourceLogoUrl: s.logoUrl,
          articleCount: 1,
        ));
      }
    }

    final extraSources = topic.perspectiveCount - logoSources.length;

    return Row(
      children: [
        if (logoSources.isNotEmpty)
          SourceLogos(sources: logoSources, colors: colors),
        if (extraSources > 0) ...[
          const SizedBox(width: 4),
          Text(
            '+$extraSources source${extraSources > 1 ? 's' : ''}',
            style: TextStyle(
              fontSize: 11,
              color: colors.textSecondary.withValues(alpha: 0.7),
            ),
          ),
        ],
        if (logoSources.isNotEmpty && timeAgo != null)
          Text(
            ' \u00b7 ',
            style: TextStyle(
              fontSize: 12,
              color: colors.textSecondary.withValues(alpha: 0.5),
            ),
          ),
        if (timeAgo != null)
          Text(
            timeAgo,
            style: TextStyle(
              fontSize: 12,
              color: colors.textSecondary,
            ),
          ),
        const Spacer(),
        Icon(
          PhosphorIcons.caretDown(PhosphorIconsStyle.bold),
          size: 14,
          color: colors.textSecondary,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Editorial mode: expanded state
  // ---------------------------------------------------------------------------

  Widget _buildExpandedEditorial(
    FacteurColors colors,
    bool isDark,
    DigestTopic topic,
    List<DigestItem> actuArticles,
    bool isActuMulti,
  ) {
    final deepArticle = topic.articles
        .where((a) => a.badge == 'pas_de_recul')
        .cast<DigestItem?>()
        .firstOrNull;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDark
            ? colors.surface.withValues(alpha: 0.3)
            : colors.surface.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colors.border.withValues(alpha: 0.15),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header fermeture ──
          _buildExpandedHeader(colors, isDark, topic),

          // ── Articles (avant "De quoi on parle") ──
          const SizedBox(height: 4),
          if (isActuMulti) ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final cardWidth = constraints.maxWidth * 0.88;
                final computedHeight =
                    _computeHeight(actuArticles, cardWidth);
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  height: computedHeight,
                  child: ClipRect(child: _buildPageView(actuArticles)),
                );
              },
            ),
            const SizedBox(height: 2),
            _buildPageIndicator(colors, actuArticles.length),
          ] else if (!actuArticles.first.isDismissed)
            _buildSingleArticle(actuArticles.first),

          const SizedBox(height: 12),

          // ── Carte "De quoi on parle ?" ──
          if (topic.introText != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.textSecondary.withValues(alpha: isDark ? 0.08 : 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'De quoi on parle ?',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      topic.introText!,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.7)
                            : colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Divergence analysis
          if (topic.divergenceAnalysis != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DivergenceAnalysisBlock(
                divergenceAnalysis: topic.divergenceAnalysis,
                biasHighlights: topic.biasHighlights,
                onCompare: _handleCompare,
                perspectiveCount: topic.perspectiveCount,
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Pas de recul
          if (deepArticle != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: PasDeReculBlock(
                deepArticle: deepArticle,
                onTap: () => widget.onArticleTap(deepArticle),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildExpandedHeader(
    FacteurColors colors,
    bool isDark,
    DigestTopic topic,
  ) {
    return GestureDetector(
      onTap: () => setState(() => _isExpanded = false),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _computeSubjects(topic) ?? topic.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              PhosphorIcons.caretUp(PhosphorIconsStyle.bold),
              size: 16,
              color: colors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // "Comparer les sources" handler
  // ---------------------------------------------------------------------------

  Future<void> _handleCompare() async {
    final articles = widget.editorialMode
        ? widget.topic.articles.where((a) => a.badge != 'pas_de_recul').toList()
        : widget.topic.articles;
    if (articles.isEmpty) return;
    final article = articles[_currentPage.clamp(0, articles.length - 1)];
    if (article.contentId.isEmpty) return;
    final repository = ref.read(feedRepositoryProvider);
    final response = await repository.getPerspectives(article.contentId);

    if (!context.mounted) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PerspectivesBottomSheet(
        perspectives: response.perspectives
            .map((p) => Perspective(
                  title: p.title,
                  url: p.url,
                  sourceName: p.sourceName,
                  sourceDomain: p.sourceDomain,
                  biasStance: p.biasStance,
                  publishedAt: p.publishedAt,
                ))
            .toList(),
        biasDistribution: response.biasDistribution,
        keywords: response.keywords,
        sourceBiasStance: response.sourceBiasStance,
        sourceName: article.source?.name ?? '',
        contentId: article.contentId,
        comparisonQuality: response.comparisonQuality,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Header
  // ---------------------------------------------------------------------------

  Widget _buildHeader(
    BuildContext context,
    FacteurColors colors,
    bool isDark,
    DigestTopic topic,
  ) {
    final labelColor =
        isDark ? const Color(0x80FFFFFF) : const Color(0x802C1E10);
    final dotColor = isDark ? const Color(0x33FFFFFF) : const Color(0x332C1E10);
    final isSingleton = topic.articles.length == 1;

    // Editorial mode: simplified header (no rank, no trending badges)
    if (widget.editorialMode) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _computeSubjects(topic) ?? _simplifyReason(topic.reason),
                style: TextStyle(
                  color: labelColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.3,
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
      );
    }

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
                  _computeSubjects(topic) ?? _simplifyReason(topic.reason),
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

          // Row 2: Badges — skip for singletons
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

  // ---------------------------------------------------------------------------
  // Article card builders (shared between editorial expanded + non-editorial)
  // ---------------------------------------------------------------------------

  /// Singleton card — natural height, no fixed SizedBox.
  Widget _buildSingleArticle(DigestItem article) {
    // Show dismiss banner if this article is being dismissed
    if (widget.activeDismissalId == article.contentId) {
      return AnimatedSize(
        duration: const Duration(milliseconds: 300),
        child: DismissBanner(
          content: _convertToContent(article),
          onUndo: widget.onDismissUndo ?? () {},
          onMuteSource: widget.onDismissMuteSource ?? () {},
          onMuteTopic: widget.onDismissMuteTopic ?? (_) {},
          onAutoResolve: widget.onDismissAutoResolve ?? () {},
        ),
      );
    }

    final imageVisible = _imageWillRender(article);
    final badgeChip = EditorialBadge.chip(article.badge, context: context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (badgeChip != null)
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 12, bottom: 14),
            child: badgeChip,
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: FeedCard(
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
            content: _convertToContent(article),
            alwaysShowDescription: !imageVisible,
            descriptionFontSize: 15,
            onImageError: () => _onImageError(article.contentId),
            onTap: () => widget.onArticleTap(article),
            onSourceTap: widget.onSourceTap != null && article.source?.id != null
                ? () => widget.onSourceTap!(article.source!.id!)
                : null,
            onSourceLongPress: () => TopicChip.showArticleSheet(
                context, _convertToContent(article),
                initialSection: ArticleSheetSection.source),
            onLongPressStart: (_) =>
                ArticlePreviewOverlay.show(context, _convertToContent(article)),
            onLongPressMoveUpdate: (details) =>
                ArticlePreviewOverlay.updateScroll(
                    details.localOffsetFromOrigin.dy),
            onLongPressEnd: (_) => ArticlePreviewOverlay.dismiss(),
            onSave: widget.onSave != null ? () => widget.onSave!(article) : null,
            onSaveLongPress: () =>
                CollectionPickerSheet.show(context, article.contentId),
            isSaved: article.isSaved,
            topicChipWidget: TopicChip(
              content: _convertToContent(article),
            ),
            isFollowedSource: article.isFollowedSource,
          ),
        ),
      ],
    );
  }

  Widget _buildPageView(List<DigestItem> articles) {
    return PageView.builder(
      controller: _pageController,
      onPageChanged: (index) => setState(() => _currentPage = index),
      itemCount: articles.length,
      itemBuilder: (context, index) {
        final article = articles[index];
        final imageVisible = _imageWillRender(article);
        final badgeChip = EditorialBadge.chip(article.badge, context: context);
        final card = FeedCard(
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
          content: _convertToContent(article),
          alwaysShowDescription: !imageVisible,
          descriptionFontSize: 15,
          onImageError: () => _onImageError(article.contentId),
          onTap: () => widget.onArticleTap(article),
          onSourceTap: widget.onSourceTap != null && article.source?.id != null
              ? () => widget.onSourceTap!(article.source!.id!)
              : null,
          onSourceLongPress: () => TopicChip.showArticleSheet(
              context, _convertToContent(article),
              initialSection: ArticleSheetSection.source),
          onLongPressStart: (_) => ArticlePreviewOverlay.show(
              context, _convertToContent(article)),
          onLongPressMoveUpdate: (details) =>
              ArticlePreviewOverlay.updateScroll(
                  details.localOffsetFromOrigin.dy),
          onLongPressEnd: (_) => ArticlePreviewOverlay.dismiss(),
          onSave: widget.onSave != null
              ? () => widget.onSave!(article)
              : null,
          onSaveLongPress: () =>
              CollectionPickerSheet.show(context, article.contentId),
          isSaved: article.isSaved,
          topicChipWidget: TopicChip(
            content: _convertToContent(article),
          ),
          isFollowedSource: article.isFollowedSource,
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

  // ---------------------------------------------------------------------------
  // Utilities
  // ---------------------------------------------------------------------------

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
      topics: item.topics,
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

  /// Returns "Sujets : X, Y, Z" from backend-computed keywords, null if empty.
  String? _computeSubjects(DigestTopic topic) {
    final subjects = topic.subjects.where((s) => s.isNotEmpty).toList();
    if (subjects.isEmpty) return null;
    return 'Sujets\u00a0: ${subjects.join(', ')}';
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
