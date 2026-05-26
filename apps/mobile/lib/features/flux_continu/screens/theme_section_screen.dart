import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../feed/models/content_model.dart';
import '../../feed/providers/feed_provider.dart';
import '../../feed/widgets/feed_carousel.dart';
import '../models/flux_continu_models.dart';
import '../providers/flux_continu_provider.dart';
import '../providers/theme_discovery_provider.dart';
import '../widgets/flux_continu_article_card.dart';
import '../widgets/section_banner.dart';
import '../widgets/theme_detail_footer.dart';

/// Distance to the bottom (in px) at which we trigger the next page of
/// articles for the current theme. Mirrors the threshold used on the main
/// Flux Continu screen so the feel of the infinite scroll is identical.
const double _kLoadMoreLeadingPx = 800.0;

/// Cap on the number of "Explorer de nouvelles sources" articles surfaced.
/// Past 6 the block stops being a discovery tease and starts to feel like a
/// secondary feed — kept short on purpose.
const int _kDiscoveryItemCap = 6;

/// Full-page view of a Tournée du jour theme section (a `FeedThemeSection`).
///
/// Surfaces the same hero banner as the inline section + the complete list of
/// articles with infinite scroll. Once the personalized feed is exhausted
/// (`!section.hasMore`), the page renders a closing block: theme-filtered
/// editorial carousels, an "Explorer de nouvelles sources" discovery list,
/// and a [ThemeDetailFooter] with "Sujet suivant" / "Retour à la Tournée".
class ThemeSectionScreen extends ConsumerStatefulWidget {
  final String sectionKeyValue;

  /// Optional snapshot captured at navigation time. Used as the immediate
  /// render source while [fluxContinuProvider] is still loading, so the user
  /// doesn't see an empty page during the slide-in transition.
  final FeedThemeSection? initialSection;

  const ThemeSectionScreen({
    super.key,
    required this.sectionKeyValue,
    this.initialSection,
  });

  @override
  ConsumerState<ThemeSectionScreen> createState() =>
      _ThemeSectionScreenState();
}

class _ThemeSectionScreenState extends ConsumerState<ThemeSectionScreen> {
  final ScrollController _scroll = ScrollController();
  bool _loadingMore = false;

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
    if (pos.maxScrollExtent - pos.pixels >= _kLoadMoreLeadingPx) return;
    if (_loadingMore) return;
    final section = _resolveSection();
    if (section == null || !section.hasMore || section.isLoadingMore) return;
    _loadingMore = true;
    ref
        .read(fluxContinuProvider.notifier)
        .loadMoreTheme(widget.sectionKeyValue)
        .whenComplete(() => _loadingMore = false);
  }

  FeedThemeSection? _resolveSection() {
    final state = ref.read(fluxContinuProvider).valueOrNull;
    if (state == null) return widget.initialSection;
    for (final s in state.sections) {
      if (s is FeedThemeSection && sectionKey(s) == widget.sectionKeyValue) {
        return s;
      }
    }
    return widget.initialSection;
  }

  void _openArticle(BuildContext context, Content article) {
    context.push(
      '${RoutePaths.fluxContinu}/content/${article.id}',
      extra: article,
    );
  }

  void _onBackToTournee() {
    Navigator.of(context).maybePop();
  }

  void _onTapNextSection(FluxSection next) {
    final key = Uri.encodeComponent(sectionKey(next));
    final path = next is FeedThemeSection
        ? '${RoutePaths.fluxContinu}/theme/$key'
        : '${RoutePaths.fluxContinu}/section/$key';
    // pushReplacement so chaining "Sujet suivant" doesn't stack N detail pages.
    // The back arrow always falls back to the Tournée.
    context.pushReplacement(path, extra: next);
  }

  /// Builds a carousel restricted to items tagged with [themeSlug] (either
  /// via [Content.topics] or via the source's macro-theme). Returns `null`
  /// when fewer than 2 items match — single-item carousels feel like padding
  /// in this context.
  FeedCarouselData? _filterCarousel(FeedCarouselData carousel, String themeSlug) {
    final filtered = <Content>[];
    final filteredBadges = <CarouselItemBadge>[];
    for (var i = 0; i < carousel.items.length; i++) {
      final item = carousel.items[i];
      final matches = item.topics.contains(themeSlug) ||
          item.source.theme == themeSlug;
      if (!matches) continue;
      filtered.add(item);
      if (i < carousel.badges.length) {
        filteredBadges.add(carousel.badges[i]);
      }
    }
    if (filtered.length < 2) return null;
    return carousel.copyWith(items: filtered, badges: filteredBadges);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    // Watch the provider so the page rebuilds when loadMoreTheme appends
    // items. Falls back to [initialSection] until the provider has a value.
    ref.watch(fluxContinuProvider);
    final section = _resolveSection();
    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: colors.backgroundPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: section == null
            ? null
            : Text(
                section.label,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
      ),
      body: section == null
          ? Center(
              child: Text(
                'Section introuvable',
                style: TextStyle(color: colors.textSecondary),
              ),
            )
          : _buildBody(section),
    );
  }

  Widget _buildBody(FeedThemeSection section) {
    final scrollExhausted = !section.hasMore;
    final themeSlug = section.themeSlug;

    return CustomScrollView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: SectionBanner(
            title: section.label,
            accent: section.accent,
            blurb: section.blurb,
            illustrationAsset: section.illustrationAsset,
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final item = section.items[index];
              return FluxContinuArticleCard(
                article: item,
                onTap: () => _openArticle(context, item),
              );
            },
            childCount: section.items.length,
          ),
        ),
        if (!scrollExhausted)
          SliverToBoxAdapter(
            child: _LoadingMoreIndicator(visible: section.isLoadingMore),
          ),
        if (scrollExhausted && themeSlug != null)
          ..._buildThemeCarousels(section, themeSlug),
        if (scrollExhausted && themeSlug != null)
          ..._buildDiscoverySection(section, themeSlug),
        if (scrollExhausted) _buildFooterSliver(section),
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }

  List<Widget> _buildThemeCarousels(
    FeedThemeSection section,
    String themeSlug,
  ) {
    final feed = ref.watch(feedProvider).valueOrNull;
    final carousels = feed?.carousels ?? const <FeedCarouselData>[];
    final filtered = <FeedCarouselData>[];
    for (final c in carousels) {
      final f = _filterCarousel(c, themeSlug);
      if (f != null) filtered.add(f);
    }
    if (filtered.isEmpty) return const [];

    return [
      SliverToBoxAdapter(
        child: _BlockHeader(label: 'À explorer dans ${section.label}'),
      ),
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: FeedCarousel(
              data: filtered[index],
              onArticleTap: (c) => _openArticle(context, c),
            ),
          ),
          childCount: filtered.length,
        ),
      ),
    ];
  }

  List<Widget> _buildDiscoverySection(
    FeedThemeSection section,
    String themeSlug,
  ) {
    final async = ref.watch(themeDiscoveryProvider(themeSlug));
    return async.when(
      data: (items) {
        final alreadyShownIds = section.items.map((c) => c.id).toSet();
        final discovery = items
            .where((c) =>
                !c.isFollowedSource && !alreadyShownIds.contains(c.id))
            .take(_kDiscoveryItemCap)
            .toList(growable: false);
        if (discovery.isEmpty) return const <Widget>[];
        return [
          const SliverToBoxAdapter(
            child: _BlockHeader(label: 'Explorer de nouvelles sources'),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final article = discovery[index];
                return FluxContinuArticleCard(
                  article: article,
                  onTap: () => _openArticle(context, article),
                );
              },
              childCount: discovery.length,
            ),
          ),
        ];
      },
      loading: () => const [
        SliverToBoxAdapter(
          child: _BlockHeader(label: 'Explorer de nouvelles sources'),
        ),
        SliverToBoxAdapter(child: _DiscoverySkeleton()),
      ],
      error: (_, __) => const <Widget>[],
    );
  }

  Widget _buildFooterSliver(FeedThemeSection section) {
    final state = ref.watch(fluxContinuProvider).valueOrNull;
    final next = state == null
        ? null
        : nextSectionAfter(state.sections, widget.sectionKeyValue);
    return SliverToBoxAdapter(
      child: ThemeDetailFooter(
        sectionLabel: section.label,
        nextSection: next,
        onTapBackToTournee: _onBackToTournee,
        onTapNextSection: next == null ? null : () => _onTapNextSection(next),
      ),
    );
  }
}

class _LoadingMoreIndicator extends StatelessWidget {
  final bool visible;

  const _LoadingMoreIndicator({required this.visible});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    if (!visible) return const SizedBox(height: 32);
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
              valueColor:
                  AlwaysStoppedAnimation<Color>(colors.textSecondary),
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

class _BlockHeader extends StatelessWidget {
  final String label;

  const _BlockHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: colors.textPrimary,
        ),
      ),
    );
  }
}

class _DiscoverySkeleton extends StatelessWidget {
  const _DiscoverySkeleton();

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Column(
      children: List.generate(3, (_) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Container(
            height: 88,
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.black.withValues(alpha: 0.04),
              ),
            ),
          ),
        );
      }),
    );
  }
}
