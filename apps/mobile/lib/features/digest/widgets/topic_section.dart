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

  /// Keys used to measure the editorial card and its header for the
  /// sticky-header effect when the card is expanded.
  final GlobalKey _editorialCardKey = GlobalKey();
  final GlobalKey _editorialHeaderKey = GlobalKey();

  /// Scroll position of the ancestor Scrollable. Used to drive the sticky
  /// header translation when the editorial card is expanded.
  ScrollPosition? _scrollPosition;

  /// Manual notifier merged into the sticky header AnimatedBuilder so we can
  /// force a recompute when the scrollable does not fire any event (e.g. after
  /// returning from a pushed route).
  final ValueNotifier<int> _stickyRefresh = ValueNotifier<int>(0);
  Listenable? _stickyListenable;

  void _updateStickyListenable() {
    final pos = _scrollPosition;
    _stickyListenable =
        pos == null ? null : Listenable.merge([pos, _stickyRefresh]);
  }

  void _scheduleStickyRefresh() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _stickyRefresh.value++;
    });
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      viewportFraction: widget.topic.articles.length > 1 ? 0.88 : 1.0,
    );
  }

  /// Route the section currently sits in. Tracked so we can detach our
  /// animation status listener when the route changes or the widget is
  /// disposed.
  ModalRoute<dynamic>? _trackedRoute;

  void _onRouteAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed ||
        status == AnimationStatus.dismissed) {
      if (mounted) _stickyRefresh.value++;
    }
  }

  void _attachRouteListeners(ModalRoute<dynamic>? route) {
    if (identical(route, _trackedRoute)) return;
    _trackedRoute?.animation?.removeStatusListener(_onRouteAnimationStatus);
    _trackedRoute?.secondaryAnimation
        ?.removeStatusListener(_onRouteAnimationStatus);
    _trackedRoute = route;
    route?.animation?.addStatusListener(_onRouteAnimationStatus);
    route?.secondaryAnimation?.addStatusListener(_onRouteAnimationStatus);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.editorialMode) {
      final newPos = Scrollable.maybeOf(context)?.position;
      if (!identical(newPos, _scrollPosition)) {
        _scrollPosition = newPos;
        _updateStickyListenable();
      } else if (_stickyListenable == null) {
        _updateStickyListenable();
      }
      // Subscribe to route transition completion so we can recompute the
      // sticky header geometry once Cupertino's slide/fade is fully settled
      // (the scrollable does not emit any event in that window).
      _attachRouteListeners(ModalRoute.of(context));
      // Force a recompute on the next frame: dependency changes commonly fire
      // when entering/leaving routes (ModalRoute, MediaQuery), and the
      // scrollable will not emit any event to retrigger the AnimatedBuilder.
      _scheduleStickyRefresh();
    }
  }

  @override
  void dispose() {
    _trackedRoute?.animation?.removeStatusListener(_onRouteAnimationStatus);
    _trackedRoute?.secondaryAnimation
        ?.removeStatusListener(_onRouteAnimationStatus);
    _pageController.dispose();
    _stickyRefresh.dispose();
    super.dispose();
  }

  /// Compute how much the editorial header should be translated vertically
  /// to stay pinned at the top of the viewport while the card is expanded.
  ///
  /// Returns 0 when the card is not yet scrolled past the pin line, and
  /// clamps to `cardHeight - headerHeight` so the sticky header releases
  /// when the card is about to scroll off-screen.
  ///
  /// Defensive against stale render-tree state (e.g. mid-route-transition):
  /// bails out when render boxes are detached, when the route is animating,
  /// or when the card is not visibly intersecting the viewport.
  double _computeStickyHeaderTranslation(BuildContext context) {
    if (!_isExpanded) return 0;

    // During route transitions, ancestor transforms (Cupertino slide, fade,
    // etc.) make `localToGlobal` return geometry that does not reflect the
    // post-transition layout. We bail out and re-compute once the route is
    // settled (see _scheduleStickyRefresh in didChangeDependencies + the
    // route animation listener).
    final route = ModalRoute.of(context);
    if (route != null) {
      final anim = route.animation;
      final secondary = route.secondaryAnimation;
      final isAnimating = (anim != null &&
              anim.status != AnimationStatus.completed &&
              anim.status != AnimationStatus.dismissed) ||
          (secondary != null &&
              secondary.status != AnimationStatus.completed &&
              secondary.status != AnimationStatus.dismissed);
      if (isAnimating) return 0;
    }

    final cardContext = _editorialCardKey.currentContext;
    final headerContext = _editorialHeaderKey.currentContext;
    if (cardContext == null || headerContext == null) return 0;

    final cardBox = cardContext.findRenderObject() as RenderBox?;
    final headerBox = headerContext.findRenderObject() as RenderBox?;
    if (cardBox == null || !cardBox.attached || !cardBox.hasSize) return 0;
    if (headerBox == null || !headerBox.attached || !headerBox.hasSize) {
      return 0;
    }

    final cardTop = cardBox.localToGlobal(Offset.zero).dy;
    final cardHeight = cardBox.size.height;
    final headerHeight = headerBox.size.height;
    final pinLine = MediaQuery.of(context).padding.top;
    final screenHeight = MediaQuery.of(context).size.height;

    // Sanity: if the card is fully off-screen (above or below the visible
    // window), don't attempt to pin the overlay — it would otherwise clamp
    // to maxTranslate and visually stick at the bottom of the card.
    if (cardTop + cardHeight <= 0 || cardTop >= screenHeight) return 0;

    final maxTranslate =
        (cardHeight - headerHeight).clamp(0.0, double.infinity);
    return (pinLine - cardTop).clamp(0.0, maxTranslate);
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
    // Badge chip above card (only outside editorial mode)
    // + 8px safety margin for text estimation variance
    final badgeHeight = widget.editorialMode ? 0.0 : _badgeHeight;
    return imageHeight + bodyHeight + _footerHeight + badgeHeight + 8.0;
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

    // After every rebuild (Riverpod state change, layout shift, etc.) the
    // sticky-header geometry may be stale because the scrollable did not
    // emit any event. Force a post-frame recompute so the AnimatedBuilder
    // picks up the new layout.
    if (widget.editorialMode && _isExpanded) _scheduleStickyRefresh();

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

      // Natural header (inside the Column), fades out when the sticky
      // overlay takes over.
      final stickyListenable = _stickyListenable;
      final naturalHeader = Padding(
        key: _editorialHeaderKey,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: _isExpanded && stickyListenable != null
            ? AnimatedBuilder(
                animation: stickyListenable,
                builder: (context, child) {
                  final translation = _computeStickyHeaderTranslation(context);
                  return Opacity(
                    opacity: translation > 0 ? 0 : 1,
                    child: child,
                  );
                },
                child: _buildHeader(context, colors, isDark, topic),
              )
            : _buildHeader(context, colors, isDark, topic),
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
              color: colors.border.withValues(alpha: isDark ? 0.28 : 0.22),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 14,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                // Card content (background + natural header + body)
                Container(
                  key: _editorialCardKey,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.11)
                      : Colors.black.withValues(alpha: 0.07),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      naturalHeader,
                      const SizedBox(height: 8),
                      if (_isExpanded)
                        _buildExpandedEditorial(colors, isDark, topic,
                            actuArticles, isActuMulti)
                      else
                        _buildCompactEditorialCard(
                            colors, isDark, topic, actuArticles),
                    ],
                  ),
                ),
                // Sticky header overlay — floats at the top of the
                // viewport while the card is scrolled past its natural
                // position, giving a "fil contenu" reading flow.
                if (_isExpanded && stickyListenable != null)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: AnimatedBuilder(
                      animation: stickyListenable,
                      builder: (context, child) {
                        final translation =
                            _computeStickyHeaderTranslation(context);
                        if (translation <= 0) {
                          return const SizedBox.shrink();
                        }
                        return Transform.translate(
                          offset: Offset(0, translation),
                          child: child,
                        );
                      },
                      child: Material(
                        color: isDark
                            ? const Color(0xFF231B12)
                            : const Color(0xFFE8DBC1),
                        elevation: 0,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: colors.border.withValues(
                                    alpha: isDark ? 0.32 : 0.22),
                                width: 0.5,
                              ),
                            ),
                          ),
                          padding:
                              const EdgeInsets.fromLTRB(12, 10, 12, 8),
                          child: _buildHeader(
                              context, colors, isDark, topic),
                        ),
                      ),
                    ),
                  ),
              ],
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
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
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
                    child: Text(
                      widget.isSerene ? 'Bonne nouvelle' : 'À la Une',
                      style: const TextStyle(
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

  Widget _buildCompactFooter(
    FacteurColors colors,
    bool isDark,
    DigestTopic topic,
    String? timeAgo,
  ) {
    // Use perspectiveSources if available, fallback to article sources
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
              color: colors.textSecondary.withValues(alpha: 0.7),
            ),
          ),
        ],
        if (visible.isNotEmpty && timeAgo != null)
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
    bool isActuMulti,
  ) {
    final deepArticle = topic.articles
        .where((a) => a.badge == 'pas_de_recul')
        .cast<DigestItem?>()
        .firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
            // ── Articles (avant "De quoi on parle") ──
            const SizedBox(height: 8),
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

            const SizedBox(height: 8),

            // ── Analyse Facteur (juste sous les carrousels) ──
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
                ),
              ),
              const SizedBox(height: 8),
            ],

            // ── Carte "De quoi on parle ?" ──
            if (topic.introText != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.textSecondary.withValues(alpha: 0.23),
                    borderRadius: BorderRadius.circular(12),
                    border: Border(
                      left: BorderSide(
                        width: 3,
                        color: colors.textSecondary.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'De quoi on parle ?',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: colors.textSecondary.withValues(alpha: 0.85),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        topic.introText!,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.85)
                              : colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],

            // ── Pas de recul ──
            if (deepArticle != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: PasDeReculBlock(
                  deepArticle: deepArticle,
                  reculIntro: deepArticle.reculIntro,
                  onTap: () => widget.onArticleTap(deepArticle),
                ),
              ),
              const SizedBox(height: 8),
            ],

            // ── Thumbs feedback ──
            ArticleThumbsFeedback(
              contentId: isActuMulti
                  ? actuArticles[_currentPage.clamp(0, actuArticles.length - 1)].contentId
                  : actuArticles.first.contentId,
            ),
          ],
    );
  }

  // ---------------------------------------------------------------------------
  // "Comparer les sources" handler
  // ---------------------------------------------------------------------------

  void _handleCompare() {
    final articles = widget.editorialMode
        ? widget.topic.articles.where((a) => a.badge != 'pas_de_recul').toList()
        : widget.topic.articles;
    if (articles.isEmpty) return;
    final article = articles[_currentPage.clamp(0, articles.length - 1)];
    if (article.contentId.isEmpty) return;

    // Kick off the request immediately and show the sheet without awaiting,
    // so the bottom sheet animates in instantly with a skeleton state instead
    // of a 2-3s freeze on the trigger button.
    final repository = ref.read(feedRepositoryProvider);
    final perspectivesFuture = repository.getPerspectives(article.contentId);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FutureBuilder<PerspectivesResponse>(
        future: perspectivesFuture,
        builder: (ctx, snapshot) {
          if (!snapshot.hasData) {
            return const PerspectivesLoadingSheet();
          }
          final response = snapshot.data!;
          return PerspectivesBottomSheet(
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
          );
        },
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
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            Text(
              ' \u2013 ',
              style: TextStyle(color: colors.textSecondary),
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
                    color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
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
                  color: colors.primary.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
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
        if (badgeChip != null && !widget.editorialMode)
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 12, bottom: 14),
            child: badgeChip,
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
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
        final badgeChip = widget.editorialMode
            ? null
            : EditorialBadge.chip(article.badge, context: context);
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
