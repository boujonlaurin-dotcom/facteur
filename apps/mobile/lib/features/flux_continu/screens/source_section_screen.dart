import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../../core/providers/navigation_providers.dart';
import '../../../widgets/article_preview_modal.dart';
import '../../digest/providers/serein_toggle_provider.dart';
import '../../feed/models/content_model.dart';
import '../../feed/providers/feed_provider.dart';
import '../../feed/widgets/feed_carousel.dart';
import '../models/flux_continu_models.dart';
import '../providers/flux_continu_provider.dart';
import '../widgets/flux_continu_article_card.dart';
import '../widgets/section_banner.dart';
import '../widgets/theme_detail_footer.dart';

/// Distance to the bottom (px) at which the next chronological page loads.
const double _kLoadMoreLeadingPx = 800.0;

/// Items per page for the source's full curation (chronological pagination).
const int _kSourcePageLimit = 10;

/// PR « Sources dans la Tournée » — full-page view of a source section
/// (`FeedThemeSection` with `kind == SectionKind.source`).
///
/// Diffère de [ThemeSectionScreen] sur trois axes :
///   1. **Pagination = curation complète chronologique** : la liste n'est PAS
///      le top-3 classé de la section (24h) mais l'intégralité de la curation
///      de la source via `getFeed(sourceId, personalized: false)` paginé. Le
///      `initialSection.items` (top classé) sert de peinture instantanée,
///      remplacé par la 1ʳᵉ page chronologique dès qu'elle arrive.
///   2. **Carrousels filtrés sur la source** (`item.source.id == sourceId`),
///      masqués si < 2 items.
///   3. **Pas de bloc « Explorer de nouvelles sources »** (une section source
///      n'invite pas à découvrir d'autres sources). La carte de clôture
///      « Vous êtes à jour » est rendue quand la curation est épuisée.
class SourceSectionScreen extends ConsumerStatefulWidget {
  final String sectionKeyValue;

  /// Snapshot capturé à la navigation — rendu immédiat le temps que la 1ʳᵉ page
  /// chronologique charge (évite une page vide pendant la transition).
  final FeedThemeSection? initialSection;

  const SourceSectionScreen({
    super.key,
    required this.sectionKeyValue,
    this.initialSection,
  });

  @override
  ConsumerState<SourceSectionScreen> createState() =>
      _SourceSectionScreenState();
}

class _SourceSectionScreenState extends ConsumerState<SourceSectionScreen> {
  final ScrollController _scroll = ScrollController(keepScrollOffset: false);

  /// Curation complète chronologique, paginée localement (indépendante du
  /// top-3 classé de la section inline).
  List<Content> _items = const [];
  int _page = 0;
  bool _hasMore = true;
  bool _loadingMore = false;
  bool _initialLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(tourneeLastDedicatedSectionProvider.notifier).state =
          widget.sectionKeyValue;
    });
    // Peinture instantanée avec le top classé de la section inline.
    _items = widget.initialSection?.items ?? const <Content>[];
    _scroll.addListener(_onScroll);
    // Charge la 1ʳᵉ page de la curation chronologique (remplace le top classé).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPage(1, replace: true);
    });
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  /// sourceId stable de la section (depuis le snapshot/résolu, fallback parse
  /// du sectionKey `source:<uuid>`).
  String? get _sourceId {
    final resolved = _resolveSection();
    final fromSection = resolved?.sourceId ?? widget.initialSection?.sourceId;
    if (fromSection != null) return fromSection;
    const prefix = 'source:';
    if (widget.sectionKeyValue.startsWith(prefix)) {
      return widget.sectionKeyValue.substring(prefix.length);
    }
    return null;
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.maxScrollExtent - pos.pixels >= _kLoadMoreLeadingPx) return;
    if (_loadingMore || !_hasMore) return;
    _loadPage(_page + 1);
  }

  Future<void> _loadPage(int page, {bool replace = false}) async {
    final sourceId = _sourceId;
    if (sourceId == null) return;
    if (_loadingMore) return;
    _loadingMore = true;
    if (mounted) setState(() {});
    try {
      final isSerene = ref.read(sereinToggleProvider).enabled;
      // `personalized: false` ⇒ curation complète chronologique (pas le scoring
      // 24h de la section inline). Flâner-grade pour une source unique.
      final response = await ref.read(feedRepositoryProvider).getFeed(
            page: page,
            limit: _kSourcePageLimit,
            sourceId: sourceId,
            serein: isSerene,
          );
      if (!mounted) return;
      setState(() {
        if (replace) {
          _items = response.items;
        } else {
          _items = [..._items, ...response.items];
        }
        _page = page;
        _initialLoaded = true;
        // Une page partielle (< limit) prouve qu'aucune page suivante n'existe,
        // quel que soit pagination.hasNext (calculé avant compression backend).
        _hasMore = response.pagination.hasNext &&
            response.items.length >= _kSourcePageLimit;
      });
    } catch (e) {
      debugPrint('SourceSectionScreen: loadPage($page) failed: $e');
      if (mounted) {
        setState(() {
          _initialLoaded = true;
        });
      }
    } finally {
      _loadingMore = false;
      if (mounted) setState(() {});
    }
  }

  FeedThemeSection? _resolveSection() {
    final state = ref.read(fluxContinuProvider).valueOrNull;
    if (state == null) return widget.initialSection;
    for (final s in state.sections) {
      if (s is FeedThemeSection &&
          s.kind == SectionKind.source &&
          sectionKey(s) == widget.sectionKeyValue) {
        return s;
      }
    }
    return widget.initialSection;
  }

  Future<void> _openArticle(BuildContext context, Content article) async {
    await context.push(
      '${RoutePaths.fluxContinu}/content/${article.id}',
      extra: article,
    );
    if (mounted) setState(() {});
  }

  void _onBackToTournee() {
    Navigator.of(context).maybePop();
  }

  void _onTapNextSection(FluxSection next) {
    ref.read(tourneeLastDedicatedSectionProvider.notifier).state = sectionKey(
      next,
    );
    final key = Uri.encodeComponent(sectionKey(next));
    final String path;
    if (next is FeedThemeSection && next.kind == SectionKind.source) {
      path = '${RoutePaths.fluxContinu}/source/$key';
    } else if (next is FeedThemeSection) {
      path = '${RoutePaths.fluxContinu}/theme/$key';
    } else {
      path = '${RoutePaths.fluxContinu}/section/$key';
    }
    // pushReplacement so chaining "suivant" doesn't stack N detail pages.
    context.pushReplacement(tourneeNextSectionLocation(path), extra: next);
  }

  /// Carrousel restreint aux items de CETTE source. Retourne `null` sous 2
  /// items (un carrousel mono-item ressemble à du remplissage ici).
  FeedCarouselData? _filterCarousel(
    FeedCarouselData carousel,
    String sourceId,
  ) {
    final filtered = <Content>[];
    final filteredBadges = <CarouselItemBadge>[];
    for (var i = 0; i < carousel.items.length; i++) {
      final item = carousel.items[i];
      if (item.source.id != sourceId) continue;
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
    // Rebuild quand la Tournée change (label/accent/logo frais).
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
    final sourceId = section.sourceId;
    final scrollExhausted = _initialLoaded && !_hasMore;
    final sourceCarousels = sourceId != null
        ? _buildSourceCarousels(section, sourceId)
        : const <Widget>[];

    return CustomScrollView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: SectionBanner(
            title: section.label,
            accent: section.accent,
            blurb: section.blurb,
            logoUrl: section.sourceLogoUrl,
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final item = _items[index];
            return FluxContinuArticleCard(
              article: item,
              onTap: () => _openArticle(context, item),
            );
          }, childCount: _items.length),
        ),
        if (_hasMore || !_initialLoaded)
          SliverToBoxAdapter(
            child: _LoadingMoreIndicator(visible: _loadingMore),
          ),
        ...sourceCarousels,
        // Pas de bloc « Explorer de nouvelles sources » (décision PO). Carte de
        // clôture quand la curation est épuisée ET aucun carrousel source.
        if (scrollExhausted && sourceCarousels.isEmpty)
          SliverToBoxAdapter(child: _SourceClosingCard(label: section.label)),
        _buildFooterSliver(section),
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }

  List<Widget> _buildSourceCarousels(
    FeedThemeSection section,
    String sourceId,
  ) {
    final feed = ref.watch(feedProvider).valueOrNull;
    final carousels = feed?.carousels ?? const <FeedCarouselData>[];
    final filtered = carousels
        .map((c) => _filterCarousel(c, sourceId))
        .whereType<FeedCarouselData>()
        .toList();
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
              onLongPressStart: (c, _) =>
                  ArticlePreviewOverlay.show(context, c),
              onLongPressMoveUpdate: (details) =>
                  ArticlePreviewOverlay.updateScroll(
                details.localOffsetFromOrigin.dy,
              ),
              onLongPressEnd: (_) => ArticlePreviewOverlay.dismiss(),
            ),
          ),
          childCount: filtered.length,
        ),
      ),
    ];
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

/// Carte de clôture de la page détail source : curation épuisée et aucun
/// carrousel source pertinent. Signale que tout a été lu pour cette source.
class _SourceClosingCard extends StatelessWidget {
  final String label;

  const _SourceClosingCard({required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            color: colors.textSecondary,
            size: 28,
          ),
          const SizedBox(height: 10),
          Text(
            'Vous êtes à jour sur $label',
            textAlign: TextAlign.center,
            style: GoogleFonts.fraunces(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              height: 1.2,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Toute la curation de cette source a été parcourue.',
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              height: 1.5,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
