import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../../core/providers/navigation_providers.dart';
import '../../../core/ui/notification_service.dart';
import '../../../widgets/article_preview_modal.dart';
import '../../detail/deck/models/article_deck.dart';
import '../../feed/models/content_model.dart';
import '../../feed/providers/feed_provider.dart';
import '../../feed/widgets/explore_section.dart';
import '../../feed/widgets/feed_carousel.dart';
import '../models/flux_continu_models.dart';
import '../providers/flux_continu_provider.dart';
import '../providers/theme_discovery_provider.dart';
import '../widgets/dismissible_article_card.dart';
import '../widgets/section_banner.dart';
import '../widgets/suggestion_reason_sheet.dart';
import '../widgets/theme_detail_footer.dart';
import '../widgets/veille_group_header.dart';

/// Distance to the bottom (in px) at which we trigger the next page of
/// articles for the current theme. Mirrors the threshold used on the main
/// Flux Continu screen so the feel of the infinite scroll is identical.
const double _kLoadMoreLeadingPx = 800.0;

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
  ConsumerState<ThemeSectionScreen> createState() => _ThemeSectionScreenState();
}

class _ThemeSectionScreenState extends ConsumerState<ThemeSectionScreen> {
  final ScrollController _scroll = ScrollController(keepScrollOffset: false);
  bool _loadingMore = false;

  /// Tours de top-up déjà consommés (cf. [_topUpIfUnderfilled]).
  int _topUpRounds = 0;

  /// Plafond de tours de top-up. Borne dure : une page dont tous les articles
  /// sont déjà rendus ailleurs dans la Tournée ne fait pas grandir la section
  /// tout en gardant `hasMore == true` — sans ce plafond on bouclerait.
  static const int _kMaxTopUpRounds = 2;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(tourneeLastDedicatedSectionProvider.notifier).state =
          widget.sectionKeyValue;
      _topUpIfUnderfilled();
    });
    _scroll.addListener(_onScroll);
  }

  /// Complète une section arrivée sous une page pleine, sans attendre le scroll.
  ///
  /// La dédup inter-sections retire d'une section les articles déjà rendus
  /// au-dessus (Essentiel, Actus du jour) **après** le slice de pagination : une
  /// section peut donc s'ouvrir avec 6-7 articles alors que le backend en a
  /// encore. L'exclusion serveur (`personalized_theme_mode`) couvre le cas
  /// nominal ; ce top-up reste le filet pour tout ce qu'elle ne voit pas
  /// (chevauchement avec une autre section thème rendue plus haut).
  ///
  /// Sans lui, l'utilisateur devait scroller sous les carrousels et « Explorer
  /// plus » pour déclencher [_onScroll] — la section paraissait close.
  void _topUpIfUnderfilled() {
    if (!mounted || _loadingMore || _topUpRounds >= _kMaxTopUpRounds) return;
    final section = _resolveSection();
    if (section == null || !section.hasMore || section.isLoadingMore) return;
    if (section.items.length >= kThemeSectionPageLimit) return;
    _topUpRounds++;
    _loadingMore = true;
    ref
        .read(fluxContinuProvider.notifier)
        .loadMoreTheme(widget.sectionKeyValue)
        .whenComplete(() {
      _loadingMore = false;
      if (!mounted) return;
      // Enchaîne le tour suivant seulement si la section est toujours maigre.
      WidgetsBinding.instance.addPostFrameCallback((_) => _topUpIfUnderfilled());
    });
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

  /// [deckArticles] — liste dont l'article fait partie : l'article s'ouvre alors
  /// dans un deck navigable au swipe (Story 34.1). Chaque bloc de la page passe
  /// **sa** liste (feed de la section, carrousel, bloc Explorer) pour que le
  /// glissement reste dans le contexte de lecture d'où vient le tap.
  Future<void> _openArticle(
    BuildContext context,
    Content article, {
    List<Content>? deckArticles,
    String? deckLabel,
  }) async {
    final deck = deckArticles == null
        ? null
        : articleDeckFromContents(
            deckArticles,
            article.id,
            sectionKey: widget.sectionKeyValue,
            sectionLabel: deckLabel ?? '',
          );
    await context.push(
      '${RoutePaths.fluxContinu}/content/${article.id}',
      extra: deck ?? article,
    );
    if (mounted) setState(() {});
  }

  void _onBackToTournee() {
    Navigator.of(context).maybePop();
  }

  /// Miroir de `flux_continu_screen._openSuggestionSheet` — même sheet
  /// « Pourquoi cette section ? », mêmes actions garder/retirer, pour que la
  /// page dédiée offre exactement la même UI que le hero du feed.
  void _openSuggestionSheet(BuildContext context, FeedThemeSection section) {
    showSuggestionReasonSheet(
      context,
      sectionTitle: section.label,
      reason: section.reason,
      onKeep: () async {
        try {
          await ref
              .read(fluxContinuProvider.notifier)
              .promoteSuggestion(section, origin: 'card');
          NotificationService.showSuccess('Ajoutée à tes favoris');
        } catch (_) {
          NotificationService.showError(
            'Impossible d\'ajouter à tes favoris pour le moment.',
          );
        }
      },
      onDismiss: () async {
        await ref.read(fluxContinuProvider.notifier).dismissSuggestion(section);
        NotificationService.showSuccess('Suggestion retirée');
      },
    );
  }

  void _onTapNextSection(FluxSection next) {
    ref.read(tourneeLastDedicatedSectionProvider.notifier).state = sectionKey(
      next,
    );
    final key = Uri.encodeComponent(sectionKey(next));
    final path = next is FeedThemeSection && next.kind == SectionKind.source
        ? '${RoutePaths.fluxContinu}/source/$key'
        : next is FeedThemeSection
            ? '${RoutePaths.fluxContinu}/theme/$key'
            : '${RoutePaths.fluxContinu}/section/$key';
    // pushReplacement so chaining "Sujet suivant" doesn't stack N detail pages.
    // The back arrow always falls back to the Tournée.
    context.pushReplacement(tourneeNextSectionLocation(path), extra: next);
  }

  /// Builds a carousel restricted to items tagged with [themeSlug] (either
  /// via [Content.topics] or via the source's macro-theme). Returns `null`
  /// when fewer than 2 items match — single-item carousels feel like padding
  /// in this context.
  FeedCarouselData? _filterCarousel(
    FeedCarouselData carousel,
    String themeSlug,
  ) {
    final filtered = <Content>[];
    final filteredBadges = <CarouselItemBadge>[];
    for (var i = 0; i < carousel.items.length; i++) {
      final item = carousel.items[i];
      final matches =
          item.topics.contains(themeSlug) || item.source.theme == themeSlug;
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

    // Carrousels + « Explorer plus » + footer (CTA « Sujet suivant ») sont
    // rendus SOUS la liste chargée, indépendamment de l'exhaustion du scroll
    // (aligné sur DigestSectionScreen). L'infinite-scroll continue d'ajouter des
    // pages d'articles AU-DESSUS ; le bloc de clôture reste en bas, toujours
    // accessible — c'est la seule route fiable vers le deep-dive.
    //
    // Pré-calcul des carrousels : permet de passer `hasThemeCarousels` à
    // _buildDiscoverySection pour qu'elle décide si la carte "Vous êtes à
    // jour" doit s'afficher (aucun carrousel ET aucun article de découverte).
    final themeCarousels = themeSlug != null
        ? _buildThemeCarousels(section, themeSlug)
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
            illustrationAsset: section.illustrationAsset,
            // Bouton réglages (tune) inline aussi sur la page dédiée veille
            // (ouverte au clic du hero) → même route « ?mode=edit » que la
            // bannière inline de la Tournée (flux_continu_screen).
            onTapSettings: section.kind == SectionKind.veille
                ? () => context.push('${RoutePaths.veilleConfig}?mode=edit')
                : null,
            // Parité avec le hero du feed : une section suggérée porte aussi
            // la balise « Choisi pour toi » + la puce « Ajouter à ton
            // Essentiel » sur sa page dédiée (miroir flux_continu_screen).
            suggested: section.isSuggested,
            onTapInfo: section.isSuggested
                ? () => _openSuggestionSheet(context, section)
                : null,
            onPromote: section.isSuggested
                ? () => ref
                    .read(fluxContinuProvider.notifier)
                    .promoteSuggestion(section, origin: 'card')
                : null,
          ),
        ),
        if (section.kind == SectionKind.veille)
          _buildVeilleSliverList(section)
        else
          SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              final item = section.items[index];
              return DismissibleArticleCard(
                key: ValueKey('theme_section_${item.id}'),
                article: item,
                analyticsOrigin: 'section_theme',
                onTap: () => _openArticle(
                  context,
                  item,
                  deckArticles: section.items,
                  deckLabel: section.label,
                ),
              );
            }, childCount: section.items.length),
          ),
        if (!scrollExhausted)
          SliverToBoxAdapter(
            child: _LoadingMoreIndicator(visible: section.isLoadingMore),
          ),
        ...themeCarousels,
        if (themeSlug != null)
          ..._buildDiscoverySection(
            section,
            themeSlug,
            hasThemeCarousels: themeCarousels.isNotEmpty,
            scrollExhausted: scrollExhausted,
          ),
        _buildFooterSliver(section),
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }

  /// SliverList du feed veille avec en-têtes « Tes sources » / « Couverture
  /// élargie » dérivés au rendu sur les transitions de `veilleGroup`. Les lignes
  /// sont reconstruites depuis la liste accumulée → l'en-tête d'un bloc apparaît
  /// une seule fois, même quand le bloc s'étale sur plusieurs pages.
  Widget _buildVeilleSliverList(FeedThemeSection section) {
    final rows = buildVeilleFeedRows(section.items);
    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final row = rows[index];
        return switch (row) {
          VeilleHeaderRow(:final label) => VeilleGroupHeader(label: label),
          VeilleArticleRow(:final content) => DismissibleArticleCard(
              key: ValueKey('veille_section_${content.id}'),
              article: content,
              analyticsOrigin: 'section_veille',
              onTap: () => _openArticle(
                context,
                content,
                deckArticles: section.items,
                deckLabel: section.label,
              ),
            ),
        };
      }, childCount: rows.length),
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
        child: ExploreBlockHeader(label: 'À explorer dans ${section.label}'),
      ),
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: FeedCarousel(
              data: filtered[index],
              onArticleTap: (c) => _openArticle(
                context,
                c,
                deckArticles: filtered[index].items,
                deckLabel: filtered[index].title,
              ),
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

  List<Widget> _buildDiscoverySection(
    FeedThemeSection section,
    String themeSlug, {
    bool hasThemeCarousels = false,
    bool scrollExhausted = false,
  }) {
    final async = ref.watch(themeDiscoveryProvider(themeSlug));
    return async.when(
      data: (items) {
        final alreadyShownIds = section.items.map((c) => c.id).toSet();
        final discovery = pickExploreItems(items, alreadyShownIds);

        if (discovery.isNotEmpty) {
          return [
            const SliverToBoxAdapter(
              child: ExploreBlockHeader(label: 'Explorer de nouvelles sources'),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final article = discovery[index];
                return DismissibleArticleCard(
                  key: ValueKey('theme_discovery_${article.id}'),
                  article: article,
                  analyticsOrigin: 'section_theme_discovery',
                  onTap: () => _openArticle(
                    context,
                    article,
                    deckArticles: discovery,
                    deckLabel: 'Explorer de nouvelles sources',
                  ),
                );
              }, childCount: discovery.length),
            ),
          ];
        }

        // Rien à montrer après les articles personnalisés : ni carrousel
        // éditorial, ni article de découverte → carte "Vous êtes à jour".
        // Gardée sur scrollExhausted pour ne pas annoncer "à jour" alors que
        // d'autres pages d'articles peuvent encore charger.
        if (scrollExhausted && !hasThemeCarousels) {
          return [
            SliverToBoxAdapter(child: _ThemeClosingCard(label: section.label)),
          ];
        }

        return const <Widget>[];
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

/// Carte de clôture affichée sur la page dédiée d'un thème quand le feed
/// personnalisé est épuisé ET qu'il n'y a ni carrousel éditorial ni article
/// de découverte de sources non-suivies. Signale à l'utilisateur qu'il a
/// tout lu sur ce thème pour le moment.
class _ThemeClosingCard extends StatelessWidget {
  final String label;

  const _ThemeClosingCard({required this.label});

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
            'Aucun autre article disponible pour le moment.',
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
