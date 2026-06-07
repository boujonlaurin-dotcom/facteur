import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../../core/providers/navigation_providers.dart';
import '../../../shared/widgets/loaders/loading_view.dart';
import '../../../widgets/article_preview_modal.dart';
import '../../flux_continu/widgets/flux_continu_article_card.dart';
import '../../flux_continu/widgets/section_banner.dart';
import '../../sources/widgets/pepites_carousel.dart';
import '../models/content_model.dart';
import '../providers/feed_provider.dart';
import '../providers/flaner_discovery_provider.dart';
import '../widgets/explore_section.dart';
import '../widgets/favorite_topic_tabs.dart' show FavoriteTabKind;
import '../widgets/feed_carousel.dart';
import '../widgets/feed_filter_bar.dart';
import '../widgets/follow_keyword_suggestion_card.dart';
import '../widgets/pin_subjects_sheet.dart';

const double _kLoadMoreLeadingPx = 800.0;
const double _kScrollDirThreshold = 12.0;

/// Sous ce seuil le footer reste révélé même en scrollant vers le bas
/// (on est effectivement « près du sommet »).
const double _kFooterRevealNearTop = 60.0;

class FlanerScreen extends ConsumerStatefulWidget {
  const FlanerScreen({super.key});

  @override
  ConsumerState<FlanerScreen> createState() => _FlanerScreenState();
}

class _FlanerScreenState extends ConsumerState<FlanerScreen> {
  final ScrollController _scroll = ScrollController();
  final Set<String> _visibleContentIds = <String>{};
  bool _loadingMore = false;
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
      // Footer auto-hide (app-wide) : les deux branches du StatefulShellRoute
      // partagent ce footer → même logique que L'Essentiel.
      updateFooterVisibility(
        ref,
        delta < 0 || currentScroll < _kFooterRevealNearTop,
      );
      _lastScrollPos = currentScroll;
    }

    if (pos.maxScrollExtent - currentScroll >= _kLoadMoreLeadingPx) return;
    if (_loadingMore) return;
    final notifier = ref.read(feedProvider.notifier);
    if (!notifier.hasNext || notifier.isLoadingMore) return;
    setState(() => _loadingMore = true);
    unawaited(
      notifier.loadMore().whenComplete(() {
        if (mounted) {
          setState(() => _loadingMore = false);
        } else {
          _loadingMore = false;
        }
      }),
    );
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
    updateFooterVisibility(ref, true);
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
    // Re-tap de l'onglet actif (depuis le shell) → remonter en haut.
    ref.listen(feedScrollTriggerProvider, (_, __) => _scrollToTop());
    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      // Header & footer vivent dans le scaffold de page partagé.
      body: SafeArea(
        top: false,
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
          // NB : le header (logo · streak · réglages) vit dans le scaffold de
          // page partagé — fixe, hors du scroll.
          const SliverToBoxAdapter(
            child: SectionBanner(
              title: 'Flâner',
              blurb: 'Tous les articles de tes sources, triés par récence.',
              accent: Color(0xFF5D4037),
              illustrationAsset: 'assets/notifications/facteur_bike.png',
              large: true,
            ),
          ),
          const SliverPersistentHeader(
            pinned: true,
            delegate: _FilterHeaderDelegate(child: _FilterSurface()),
          ),
          const SliverToBoxAdapter(child: PinSubjectsBanner()),
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
          ..._buildExploreSlivers(state),
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

  /// Bloc « Explorer de nouvelles sources » affiché sous la liste quand un
  /// onglet de découverte (sujet / thème / entité) est actif. Le bloc principal
  /// ne montre que les sources suivies (`followed_only`, rapide) ; ces articles
  /// de sources non-suivies chargent **en parallèle** via
  /// [flanerDiscoveryProvider] sans bloquer le rendu. Calque la section
  /// « Explorer » de la page de section de la Tournée.
  List<Widget> _buildExploreSlivers(FeedState state) {
    final selection = ref.watch(feedFilterSelectionProvider);
    final FlanerDiscoveryArg? arg;
    if (selection.topic != null) {
      arg = FlanerDiscoveryArg(
        kind: FavoriteTabKind.subjectTopic,
        slug: selection.topic!,
      );
    } else if (selection.theme != null) {
      arg = FlanerDiscoveryArg(
        kind: FavoriteTabKind.theme,
        slug: selection.theme!,
      );
    } else if (selection.entity != null) {
      arg = FlanerDiscoveryArg(
        kind: FavoriteTabKind.subjectEntity,
        slug: selection.entity!,
      );
    } else {
      // Vue par défaut, onglet Source ou mot-clé → pas de bloc Explorer.
      return const <Widget>[];
    }

    final async = ref.watch(flanerDiscoveryProvider(arg));
    return async.when(
      data: (items) {
        final alreadyShownIds = state.items.map((c) => c.id).toSet();
        final discovery = pickExploreItems(items, alreadyShownIds);
        if (discovery.isEmpty) return const <Widget>[];
        return [
          const SliverToBoxAdapter(
            child: ExploreBlockHeader(label: 'Explorer de nouvelles sources'),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final article = discovery[index];
                return FluxContinuArticleCard(
                  article: article,
                  onTap: () => _openArticle(article),
                );
              },
              childCount: discovery.length,
            ),
          ),
        ];
      },
      loading: () => const [
        SliverToBoxAdapter(
          child: ExploreBlockHeader(label: 'Explorer de nouvelles sources'),
        ),
        SliverToBoxAdapter(child: ExploreDiscoverySkeleton()),
      ],
      error: (_, __) => const <Widget>[],
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
            child: FeedFilterBar(),
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
