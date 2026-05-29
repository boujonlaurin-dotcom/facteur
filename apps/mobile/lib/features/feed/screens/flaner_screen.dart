import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../../shared/widgets/loaders/loading_view.dart';
import '../../../shared/widgets/navigation/main_bottom_nav.dart';
import '../../../widgets/article_preview_modal.dart';
import '../../../widgets/design/facteur_logo.dart';
import '../../app_update/providers/app_update_provider.dart';
import '../../flux_continu/widgets/flux_continu_article_card.dart';
import '../../gamification/widgets/streak_indicator.dart';
import '../../sources/widgets/pepites_carousel.dart';
import '../models/content_model.dart';
import '../providers/feed_provider.dart';
import '../widgets/feed_carousel.dart';
import '../widgets/feed_filter_bar.dart';
import '../widgets/follow_keyword_suggestion_card.dart';
import '../widgets/profile_avatar_button.dart';

const double _kLoadMoreLeadingPx = 800.0;
const double _kScrollDirThreshold = 12.0;
const double _kFabHideAboveScroll = 380.0;

class FlanerScreen extends ConsumerStatefulWidget {
  const FlanerScreen({super.key});

  @override
  ConsumerState<FlanerScreen> createState() => _FlanerScreenState();
}

class _FlanerScreenState extends ConsumerState<FlanerScreen> {
  final ScrollController _scroll = ScrollController();
  final Set<String> _visibleContentIds = <String>{};
  bool _loadingMore = false;
  bool _showScrollTopFab = false;
  double _lastScrollPos = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final currentScroll = pos.pixels;

    final delta = currentScroll - _lastScrollPos;
    if (delta.abs() >= _kScrollDirThreshold) {
      bool nextFab = _showScrollTopFab;
      if (currentScroll < _kFabHideAboveScroll) {
        nextFab = false;
      } else if (delta < 0) {
        nextFab = true;
      } else if (delta > 0) {
        nextFab = false;
      }
      if (nextFab != _showScrollTopFab) {
        setState(() => _showScrollTopFab = nextFab);
      }
      _lastScrollPos = currentScroll;
    }

    if (pos.maxScrollExtent - currentScroll >= _kLoadMoreLeadingPx) return;
    if (_loadingMore) return;
    final notifier = ref.read(feedProvider.notifier);
    if (!notifier.hasNext || notifier.isLoadingMore) return;
    setState(() => _loadingMore = true);
    unawaited(notifier.loadMore().whenComplete(() {
      if (mounted) {
        setState(() => _loadingMore = false);
      } else {
        _loadingMore = false;
      }
    }));
  }

  Future<void> _refresh() async {
    final ids = Set<String>.from(_visibleContentIds);
    _visibleContentIds.clear();
    await ref.read(feedProvider.notifier).refreshArticlesWithSnapshot(ids);
  }

  Future<void> _openArticle(Content article) async {
    await context.push(
      '${RoutePaths.flaner}/content/${article.id}',
      extra: article,
    );
    if (!mounted) return;
    unawaited(ref.read(feedProvider.notifier).markContentAsConsumed(article));
  }

  Future<void> _scrollToTop() async {
    if (!_scroll.hasClients) return;
    unawaited(HapticFeedback.lightImpact());
    await _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeInOutCubic,
    );
  }

  void _markVisible(String contentId) {
    if (contentId.isNotEmpty) _visibleContentIds.add(contentId);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(feedProvider);
    final colors = context.facteurColors;
    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      bottomNavigationBar: const MainBottomNav(
        current: MainBottomNavDestination.flaner,
      ),
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            async.when(
              loading: () => const LoadingView(),
              error: (e, _) => _ErrorView(
                error: e,
                onRetry: () => ref.read(feedProvider.notifier).refresh(),
              ),
              data: (state) => _buildContent(context, state),
            ),
            Positioned(
              right: 16,
              bottom: 24,
              child: SafeArea(
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  offset:
                      _showScrollTopFab ? Offset.zero : const Offset(0, 1.6),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    opacity: _showScrollTopFab ? 1.0 : 0.0,
                    child: _ScrollToTopButton(onTap: _scrollToTop),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, FeedState state) {
    final colors = context.facteurColors;
    final keyword = ref.watch(feedProvider.notifier).selectedKeyword;
    return RefreshIndicator(
      onRefresh: _refresh,
      color: colors.primary,
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(child: _Header()),
          const SliverPersistentHeader(
            pinned: true,
            delegate: _FilterHeaderDelegate(child: _FilterSurface()),
          ),
          SliverToBoxAdapter(
            child: (keyword == null || keyword.trim().isEmpty)
                ? const SizedBox.shrink()
                : FollowKeywordSuggestionCard(keyword: keyword),
          ),
          if (state.items.length > 4)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: PepitesCarousel(),
              ),
            ),
          _buildFeedList(state),
          if (_loadingMore)
            const SliverToBoxAdapter(child: _LoadingMoreIndicator()),
          const SliverToBoxAdapter(child: SizedBox(height: 92)),
        ],
      ),
    );
  }

  Widget _buildFeedList(FeedState state) {
    final contents = state.items;
    final carousels = state.carousels;
    final intercalations = <({int position, Widget Function() builder})>[];

    for (final carousel in carousels) {
      if (carousel.items.isEmpty || carousel.position >= contents.length) {
        continue;
      }
      intercalations.add((
        position: carousel.position,
        builder: () => Padding(
              key: ValueKey('flaner_carousel_${carousel.carouselType}'),
              padding: const EdgeInsets.only(bottom: 12),
              child: FeedCarousel(
                data: carousel,
                onArticleTap: _openArticle,
                onLongPressStart: (c, _) =>
                    ArticlePreviewOverlay.show(context, c),
                onLongPressMoveUpdate: (details) =>
                    ArticlePreviewOverlay.updateScroll(
                  details.localOffsetFromOrigin.dy,
                ),
                onLongPressEnd: (_) => ArticlePreviewOverlay.dismiss(),
                onItemVisible: _markVisible,
              ),
            ),
      ));
    }

    intercalations.sort((a, b) => a.position.compareTo(b.position));

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, listIndex) {
        int offset = 0;
        for (final inter in intercalations) {
          final effective = inter.position + offset;
          if (listIndex == effective) return inter.builder();
          if (listIndex > effective) offset++;
        }
        final articleIndex = listIndex - offset;
        if (articleIndex < 0 || articleIndex >= contents.length) {
          return null;
        }
        final article = contents[articleIndex];
        return VisibilityDetector(
          key: ValueKey('flaner_visible_${article.id}'),
          onVisibilityChanged: (info) {
            if (info.visibleFraction >= 0.9) _markVisible(article.id);
          },
          child: FluxContinuArticleCard(
            article: article,
            onTap: () => _openArticle(article),
            onSwipeDismiss: () =>
                ref.read(feedProvider.notifier).swipeDismiss(article),
          ),
        );
      }, childCount: contents.length + intercalations.length),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FacteurSpacing.space6,
        vertical: FacteurSpacing.space3,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const FacteurLogo(size: 22, showIcon: false),
          const Align(
            alignment: Alignment.centerLeft,
            child: StreakIndicator(),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Consumer(
              builder: (context, ref, _) {
                final hasUpdate =
                    ref.watch(appUpdateProvider).valueOrNull?.updateAvailable ==
                        true;
                final settingsButton = ProfileAvatarButton(
                  onTap: () => context.push(RoutePaths.settings),
                );
                if (!hasUpdate) return settingsButton;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    settingsButton,
                    Positioned(
                      top: -2,
                      right: -2,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: colors.error,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: colors.backgroundPrimary,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterSurface extends ConsumerWidget {
  const _FilterSurface();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final refreshing = ref.watch(feedRefreshingProvider);
    return Material(
      color: colors.backgroundPrimary,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: FeedFilterBar(excludedThemeSlugs: <String>[]),
          ),
          SizedBox(
            height: 2,
            child: refreshing
                ? LinearProgressIndicator(
                    minHeight: 2,
                    backgroundColor: Colors.transparent,
                    color: colors.primary,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _FilterHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  const _FilterHeaderDelegate({required this.child});

  @override
  double get minExtent => 56;

  @override
  double get maxExtent => 56;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _FilterHeaderDelegate oldDelegate) {
    return oldDelegate.child != child;
  }
}

class _LoadingMoreIndicator extends StatelessWidget {
  const _LoadingMoreIndicator();

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(colors.textSecondary),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Chargement…',
            style: TextStyle(
              color: colors.textSecondary,
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScrollToTopButton extends StatelessWidget {
  final VoidCallback onTap;

  const _ScrollToTopButton({required this.onTap});

  static const _kRadius = BorderRadius.all(Radius.circular(22));

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final isDark = context.isDarkMode;
    final fillColor = isDark
        ? colors.backgroundPrimary.withValues(alpha: 0.78)
        : const Color.fromRGBO(242, 232, 213, 0.82);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : const Color.fromRGBO(0, 0, 0, 0.08);

    return ClipRRect(
      borderRadius: _kRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: _kRadius,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: fillColor,
                borderRadius: _kRadius,
                border: Border.all(color: borderColor),
              ),
              child: Icon(
                Icons.keyboard_arrow_up_rounded,
                color: colors.textPrimary,
                size: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Impossible de charger Flâner',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: const Text('Réessayer')),
          ],
        ),
      ),
    );
  }
}
