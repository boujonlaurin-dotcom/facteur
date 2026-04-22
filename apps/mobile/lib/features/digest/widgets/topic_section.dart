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
import '../../feed/repositories/feed_repository.dart';
import '../providers/digest_provider.dart';
import '../../feed/utils/article_title_layout.dart';
import '../../feed/widgets/dismiss_banner.dart';
import '../../feed/widgets/feed_card.dart';
import '../../feed/widgets/initial_circle.dart';
import '../../../widgets/design/facteur_image.dart';
import '../../feed/widgets/perspectives_bottom_sheet.dart';
import '../../feed/widgets/perspectives_loading_sheet.dart';
import '../../saved/widgets/collection_picker_sheet.dart';
import '../../sources/models/source_model.dart';
import '../models/digest_models.dart';
import 'article_thumbs_feedback.dart';
import 'divergence_analysis_block.dart';
import 'editorial_badge.dart';
import 'pas_de_recul_block.dart';
import 'topic_theme_chip.dart';

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
  final int totalTopics;

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
    this.totalTopics = 5,
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

  /// Singleton mode — always display a single article per topic (no
  /// carousel, no page indicator). Priority:
  ///   1. A followed-source article in the pool (user affinity bonus),
  ///   2. otherwise the first actu_article (pivot rank 1, also the anchor
  ///      the backend used to compute perspectives / bias distribution).
  DigestItem _pickSingleton(List<DigestItem> actuArticles) {
    for (final a in actuArticles) {
      if (a.isFollowedSource) return a;
    }
    return actuArticles.first;
  }

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

  /// Digest card titles get more room than feed cards — 5 lines in the
  /// expanded FeedCard and the compact card variants. The hero variant
  /// keeps its tighter 3-line budget because the stacked image + gradient
  /// already constrains vertical space visually. Feed cards are unchanged
  /// (FeedCard defaults titleMaxLines to 3).
  static const int _digestTitleMaxLines = 5;
  static const int _digestHeroTitleMaxLines = 3;

  /// Footer height: border (1) + padding (4×2) + icon row (~28) = ~37
  static const double _footerHeight = 57.0;

  /// Body padding top + bottom (denseLayout: 10 × 2 = 20)
  static const double _bodyPadding = 20.0;

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

    final imageHeight = hasImage ? cardWidth / (3 / 2) : 0.0;
    // Badge chip above card (only outside editorial mode).
    // Estimation volontairement serrée ; tout écart résiduel est
    // absorbé par Align(center) dans _buildPageView (moitié/moitié).
    final badgeHeight = widget.editorialMode ? 0.0 : _badgeHeight;
    return imageHeight + bodyHeight + _footerHeight + badgeHeight;
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

    // Editorial mode: toggle expand/collapse. The carousel is gone —
    // editorial topics always render as a singleton (_pickSingleton).
    // Extras still drive perspective_count / bias_distribution downstream.
    if (widget.editorialMode) {
      final actuArticles = topic.articles
          .where((a) => a.badge != 'pas_de_recul')
          .toList();
      if (actuArticles.isEmpty) return const SizedBox.shrink();

      // Plain header pinned at the top of the card (no sticky overlay).
      // The previous sticky-overlay implementation was fragile across route
      // transitions and Riverpod-driven rebuilds — see git history.
      final naturalHeader = Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: _buildHeader(context, colors, isDark, topic),
      );

      return AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: Alignment.topCenter,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
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
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              color: isDark
                  ? Colors.white.withOpacity(0.05)
                  : Colors.black.withOpacity(0.025),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  naturalHeader,
                  const SizedBox(height: 8),
                  if (_isExpanded)
                    _buildExpandedEditorial(
                        colors, isDark, topic, actuArticles)
                  else
                    _buildCompactEditorialCard(
                        colors, isDark, topic, actuArticles),
                ],
              ),
            ),
          ),
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
    final article = _pickSingleton(actuArticles);
    final hasImage = _imageWillRender(article);
    final timeAgo = article.publishedAt != null
        ? timeago
            .format(article.publishedAt!, locale: 'fr_short')
            .replaceAll('il y a ', '')
        : null;

    final isHero = topic.isUne && hasImage;

    return GestureDetector(
      onTap: () {
        // Tap on compact preview = "reading" the article in the user's model.
        // Mark as read immediately so the progress bar reflects the action,
        // then expand. Avoid re-firing when already read/dismissed.
        if (!article.isRead && !article.isDismissed) {
          ref
              .read(digestProvider.notifier)
              .applyAction(article.contentId, 'read');
        }
        setState(() => _isExpanded = true);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.06) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: isHero
              ? Border(
                  left: BorderSide(width: 3, color: colors.primary),
                )
              : null,
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
                    maxLines: _digestTitleMaxLines,
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
                  _buildCompactFooter(colors, isDark, topic, timeAgo, article),
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
            maxLines: _digestTitleMaxLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              height: 1.3,
              color: isDark ? Colors.white : colors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          _buildCompactFooter(colors, isDark, topic, timeAgo, article),
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
                      Colors.black.withOpacity(0.7),
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
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      widget.isSerene ? 'Bonne nouvelle' : 'À la Une',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    article.title,
                    maxLines: _digestHeroTitleMaxLines,
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
          child: _buildCompactFooter(colors, isDark, topic, timeAgo, article),
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
          Text(
            article.title,
            maxLines: _digestTitleMaxLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              height: 1.3,
              color: isDark ? Colors.white : colors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          _buildCompactFooter(colors, isDark, topic, timeAgo, article),
        ],
      ),
    );
  }

  Widget _buildCompactFooter(
    FacteurColors colors,
    bool isDark,
    DigestTopic topic,
    String? timeAgo,
    DigestItem singleton,
  ) {
    // Use perspectiveSources if available, fallback to article sources.
    final List<({String? id, String name, String? logoUrl})> allSources;
    if (topic.perspectiveSources.isNotEmpty) {
      final seen = <String>{};
      allSources = topic.perspectiveSources
          .where((s) => seen.add(s.name))
          .map((s) => (id: s.id, name: s.name, logoUrl: s.logoUrl))
          .toList();
    } else {
      final seen = <String>{};
      allSources = <({String? id, String name, String? logoUrl})>[];
      for (final a in topic.articles) {
        final s = a.source;
        if (s != null && s.id != null && seen.add(s.id!)) {
          allSources.add((id: s.id, name: s.name, logoUrl: s.logoUrl));
        }
      }
    }

    // Pin the singleton's source first so the big (20px) logo visually
    // matches the article rendered in the card. Match on id when possible,
    // fall back to name for backends that don't populate source_id on
    // perspective_sources (Google News entries).
    final singletonSource = singleton.source;
    final singletonId = singletonSource?.id;
    final singletonName = singletonSource?.name;
    if (singletonSource != null) {
      final idx = allSources.indexWhere(
        (s) => (singletonId != null && s.id == singletonId) ||
            (singletonName != null && s.name == singletonName),
      );
      if (idx > 0) {
        final pinned = allSources.removeAt(idx);
        allSources.insert(0, pinned);
      } else if (idx < 0) {
        // Singleton source isn't in perspective_sources (e.g. unknown bias
        // filtered upstream). Prepend it so the visual anchor holds.
        allSources.insert(
          0,
          (
            id: singletonId,
            name: singletonName ?? 'Inconnu',
            logoUrl: singletonSource.logoUrl,
          ),
        );
      }
    }

    const maxLogos = 4;
    final visible = allSources.take(maxLogos).toList();
    final extraCount = allSources.length - visible.length;

    return Row(
      children: [
        for (var i = 0; i < visible.length; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          _buildLogoCircle(
            name: visible[i].name,
            logoUrl: visible[i].logoUrl,
            size: i == 0 ? 20.0 : 14.0,
            colors: colors,
          ),
        ],
        if (extraCount > 0) ...[
          const SizedBox(width: 4),
          Text(
            '+$extraCount',
            style: TextStyle(
              fontSize: 11,
              color: colors.textSecondary.withOpacity(0.7),
            ),
          ),
        ],
        if (visible.isNotEmpty && timeAgo != null)
          Text(
            ' \u00b7 ',
            style: TextStyle(
              fontSize: 12,
              color: colors.textSecondary.withOpacity(0.5),
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

  Widget _buildLogoCircle({
    required String name,
    required String? logoUrl,
    required double size,
    required FacteurColors colors,
  }) {
    final hasLogo = logoUrl != null && logoUrl.isNotEmpty;
    if (hasLogo) {
      return ClipOval(
        child: FacteurImage(
          imageUrl: logoUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorWidget: (context) => InitialCircle(
            initial: name.isNotEmpty ? name[0].toUpperCase() : '?',
            colors: colors,
            size: size,
          ),
        ),
      );
    }
    return InitialCircle(
      initial: name.isNotEmpty ? name[0].toUpperCase() : '?',
      colors: colors,
      size: size,
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
  ) {
    final deepArticle = topic.articles
        .where((a) => a.badge == 'pas_de_recul')
        .cast<DigestItem?>()
        .firstOrNull;

    // Singleton mode: show one article per topic even when the backend
    // sends 2-3 (carousel deprecated — see review iteration). The extras
    // still drive `perspective_sources` / `bias_distribution` for the
    // "Analyse de biais" block below.
    final singleton = _pickSingleton(actuArticles);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
            // ── Article unique (singleton) ──
            const SizedBox(height: 2),
            if (!singleton.isDismissed) _buildSingleArticle(singleton),

            const SizedBox(height: 12),

            // ── Analyse Facteur (juste sous le singleton) ──
            if (topic.divergenceAnalysis != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: DivergenceAnalysisBlock(
                  divergenceAnalysis: topic.divergenceAnalysis,
                  biasHighlights: topic.biasHighlights,
                  biasDistribution: topic.biasDistribution,
                  divergenceLevel: topic.divergenceLevel,
                  onCompare: _handleCompare,
                  perspectiveCount: topic.perspectiveCount,
                  perspectiveSources: topic.perspectiveSources,
                  excludeSourceId: singleton.source?.id,
                  excludeSourceName: singleton.source?.name,
                ),
              ),
              const SizedBox(height: 6),
            ],

            // ── Pas de recul (intègre le contexte du sujet) ──
            if (deepArticle != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: PasDeReculBlock(
                  deepArticle: deepArticle,
                  introText: topic.introText,
                  onTap: () => widget.onArticleTap(deepArticle),
                ),
              ),
              const SizedBox(height: 6),
            ] else if (topic.introText != null) ...[
              // Fallback : sujet sans deep article → intro text en
              // paragraphe discret (pas de carte).
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  topic.introText!,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: isDark
                        ? Colors.white.withOpacity(0.75)
                        : colors.textSecondary.withOpacity(0.85),
                  ),
                ),
              ),
              const SizedBox(height: 6),
            ],

            // ── Thumbs feedback ──
            ArticleThumbsFeedback(
              contentId: singleton.contentId,
            ),
          ],
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
    // Editorial mode is singleton — use the same selection logic as the
    // compact card so "Comparer" operates on the visible article. Non-
    // editorial paths keep the legacy _currentPage behavior.
    final article = widget.editorialMode
        ? _pickSingleton(articles)
        : articles[_currentPage.clamp(0, articles.length - 1)];
    // Prefer the backend-provided pivot id (the same content used to compute
    // perspective_count / bias_distribution). Falls back to the currently
    // displayed article for legacy cached digests where the field is absent.
    final pivotId = (widget.topic.representativeContentId?.isNotEmpty ?? false)
        ? widget.topic.representativeContentId!
        : article.contentId;
    if (pivotId.isEmpty) return;
    final repository = ref.read(feedRepositoryProvider);
    final response = await repository.getPerspectives(pivotId);
    if (!mounted) return;

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
        // Pass the same pivot used to fetch perspectives so any follow-up
        // action (e.g. analyzePerspectives) operates on the same content.
        contentId: pivotId,
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

    // Editorial mode: rank + badge + theme chip
    if (widget.editorialMode) {
      final mainBadge =
          topic.articles.isNotEmpty ? topic.articles.first.badge : null;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            Text(
              '${topic.rank}',
              style: TextStyle(
                color: colors.textSecondary.withOpacity(0.7),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            Text(
              ' \u2013 ',
              style: TextStyle(color: colors.textSecondary.withOpacity(0.5)),
            ),
            EditorialBadge.chip(mainBadge, context: context) ??
                const SizedBox.shrink(),
            const SizedBox(width: 8),
            TopicThemeChip(themeSlug: topic.theme),
            const Spacer(),
            if (topic.isCovered)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
                  size: 16,
                  color: colors.success,
                ),
              ),
            if (_isExpanded)
              GestureDetector(
                onTap: () => setState(() => _isExpanded = false),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white : Colors.black).withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    PhosphorIcons.caretUp(PhosphorIconsStyle.bold),
                    size: 14,
                    color: colors.textSecondary,
                  ),
                ),
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
                  color: colors.primary.withOpacity(0.6),
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  letterSpacing: 0.5,
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
                    fontSize: 10,
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
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: colors.primary.withOpacity(isDark ? 0.15 : 0.10),
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
              fontSize: 10,
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
        if (badgeChip != null && !widget.editorialMode)
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 12, bottom: 14),
            child: badgeChip,
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: FeedCard(
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
            content: _convertToContent(article),
            alwaysShowDescription: !imageVisible,
            descriptionFontSize: 15,
            titleMaxLines: _digestTitleMaxLines,
            denseLayout: true,
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
        final badgeChip = widget.editorialMode
            ? null
            : EditorialBadge.chip(article.badge, context: context);
        final card = FeedCard(
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
          content: _convertToContent(article),
          alwaysShowDescription: !imageVisible,
          descriptionFontSize: 15,
          titleMaxLines: _digestTitleMaxLines,
          denseLayout: true,
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
            alignment: Alignment.center,
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
                : colors.textTertiary.withOpacity(0.3),
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
