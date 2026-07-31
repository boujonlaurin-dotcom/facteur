import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../../core/nudges/nudge_coordinator.dart';
import '../../../core/nudges/nudge_ids.dart';
import '../../../core/nudges/widgets/feed_nudge_anchors.dart';
import '../../../core/providers/analytics_provider.dart';
import '../../../core/providers/navigation_providers.dart';
import '../../../shared/widgets/loaders/loading_view.dart';
import '../../../widgets/article_preview_modal.dart';
import '../../flux_continu/widgets/flux_continu_article_card.dart';
import '../../flux_continu/widgets/section_banner.dart';
import '../../flux_continu/widgets/section_block.dart' show FluxFeedbackChip;
import '../../custom_topics/widgets/topic_chip.dart';
import '../../release_notes/widgets/changelog_banner.dart';
import '../../sources/add_source_bridge.dart';
import '../../sources/widgets/pepites_carousel.dart';
import '../models/content_model.dart';
import '../providers/active_filter_label_provider.dart';
import '../providers/feed_provider.dart';
import '../providers/flaner_discovery_provider.dart';
import '../providers/search_navigation_provider.dart';
import '../utils/empty_search_reporter.dart';
import '../widgets/empty_filter_state.dart';
import '../widgets/explore_section.dart';
import '../widgets/favorite_topic_tabs.dart' show FavoriteTabKind;
import '../widgets/feed_carousel.dart';
import '../widgets/feed_filter_bar.dart';
import '../widgets/feedback_inline.dart';
import '../widgets/follow_keyword_suggestion_card.dart';
import '../widgets/pin_subjects_sheet.dart';
import '../widgets/widget_cta_banner.dart';

const double _kLoadMoreLeadingPx = 800.0;

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
  final Set<String> _pendingFeedback = <String>{};
  bool _gestureNudgeRequested = false;
  bool _showSwipeHint = false;

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

    // Footer auto-hide (app-wide) : ne se cache QUE sur un scroll-down
    // utilisateur réel (`userScrollDirection`), pas sur un delta de position —
    // sinon un ré-ajustement programmatique du scroll masquerait le footer sans
    // intention de l'utilisateur. Même logique que L'Essentiel.
    if (currentScroll < _kFooterRevealNearTop) {
      updateFooterVisibility(ref, true);
    } else if (pos.userScrollDirection == ScrollDirection.reverse) {
      updateFooterVisibility(ref, false);
    } else if (pos.userScrollDirection == ScrollDirection.forward) {
      updateFooterVisibility(ref, true);
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
    if (_pendingFeedback.isNotEmpty && mounted) {
      setState(_pendingFeedback.clear);
    }
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

  void _scheduleGestureNudge() {
    if (_gestureNudgeRequested) return;
    _gestureNudgeRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final location =
          GoRouter.of(context).routerDelegate.currentConfiguration.uri.path;
      if (!location.startsWith(RoutePaths.flaner)) {
        _gestureNudgeRequested = false;
        return;
      }
      final coordinator = ref.read(nudgeCoordinatorProvider);
      if (coordinator.activeId != null) return;
      final swipe = await coordinator.request(NudgeIds.feedSwipeHint);
      if (!mounted) return;
      if (swipe == NudgeIds.feedSwipeHint) {
        setState(() => _showSwipeHint = true);
        return;
      }
      if (coordinator.activeId == null) {
        await coordinator.request(NudgeIds.feedPreviewLongpress);
      }
    });
  }

  void _onSwipeHintComplete() {
    if (mounted) setState(() => _showSwipeHint = false);
    final coordinator = ref.read(nudgeCoordinatorProvider);
    if (coordinator.activeId == NudgeIds.feedSwipeHint) {
      unawaited(coordinator.dismiss(markSeen: false));
    }
  }

  void _recordSwipeConversion() {
    if (_showSwipeHint && mounted) {
      setState(() => _showSwipeHint = false);
    }
    unawaited(
      ref
          .read(nudgeCoordinatorProvider)
          .recordConversion(NudgeIds.feedSwipeHint),
    );
  }

  void _recordLongPressConversion() {
    unawaited(
      ref
          .read(nudgeCoordinatorProvider)
          .recordConversion(NudgeIds.feedPreviewLongpress),
    );
  }

  void _onSwipeDismiss(Content article) {
    unawaited(ref.read(feedProvider.notifier).markHiddenRemote(article));
    setState(() => _pendingFeedback.add(article.id));
  }

  void _resolveFeedback(String contentId) {
    if (!_pendingFeedback.remove(contentId)) return;
    setState(() {});
    ref.read(feedProvider.notifier).confirmDismiss(contentId);
  }

  void _undoFeedback(Content article) {
    unawaited(ref.read(feedProvider.notifier).undoHide(article));
    setState(() => _pendingFeedback.remove(article.id));
  }

  void _trackFeedback(String contentId, String feedbackType) {
    unawaited(
      ref.read(analyticsServiceProvider).trackArticleFeedbackSubmitted(
            contentId: contentId,
            feedbackType: feedbackType,
            origin: 'flaner',
          ),
    );
  }

  Future<void> _selectFeedback(Content article, FluxFeedbackChip chip) async {
    switch (chip) {
      case FluxFeedbackChip.source:
        _trackFeedback(article.id, 'less_source');
        await TopicChip.showArticleSheet(
          context,
          article,
          initialSection: ArticleSheetSection.source,
          highlightInitialSection: true,
        );
        if (mounted) _resolveFeedback(article.id);
      case FluxFeedbackChip.topic:
        _trackFeedback(article.id, 'less_topic');
        await TopicChip.showArticleSheet(
          context,
          article,
          initialSection: ArticleSheetSection.topic,
          highlightInitialSection: true,
        );
        if (mounted) _resolveFeedback(article.id);
      case FluxFeedbackChip.alreadySeen:
        _trackFeedback(article.id, 'already_seen');
        _resolveFeedback(article.id);
    }
  }

  Widget _feedbackInline(Content article) {
    return Padding(
      key: ValueKey('flaner_feedback_${article.id}'),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: FeedbackInline(
        onSelectSource: () => _selectFeedback(article, FluxFeedbackChip.source),
        onSelectTopic: () => _selectFeedback(article, FluxFeedbackChip.topic),
        onSelectAlreadySeen: () =>
            _selectFeedback(article, FluxFeedbackChip.alreadySeen),
        onUndo: () => _undoFeedback(article),
        onClose: () => _resolveFeedback(article.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(feedProvider);
    final colors = context.facteurColors;
    // Re-tap de l'onglet actif (depuis le shell) → remonter en haut.
    ref.listen(feedScrollTriggerProvider, (_, __) => _scrollToTop());
    _watchEmptySearch();
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

  /// Élargit la recherche mot-clé courante aux sources non suivies.
  Future<void> _broadenSearch(String keyword, int resultCount) async {
    unawaited(HapticFeedback.mediumImpact());
    unawaited(
      ref.read(analyticsServiceProvider).trackSearchBroadened(
            resultCount: resultCount,
          ),
    );
    await ref
        .read(feedProvider.notifier)
        .setKeyword(keyword, includeUnfollowed: true);
  }

  final _emptySearchReporter = EmptySearchReporter();

  /// Émet `search_submitted_empty` une fois par recherche bredouille.
  ///
  /// Le `ref.listen` seul rate le cas « recherche lancée depuis L'Essentiel » :
  /// le feed est déjà résolu et vide quand cet écran se monte, donc aucune
  /// notification n'arrive. On inspecte donc aussi l'état **courant**.
  void _watchEmptySearch() {
    ref.listen<AsyncValue<FeedState>>(
      feedProvider,
      (previous, next) => _reportIfEmptySearch(next),
    );
    _reportIfEmptySearch(ref.read(feedProvider));
  }

  void _reportIfEmptySearch(AsyncValue<FeedState> async) {
    final selection = ref.read(feedFilterSelectionProvider);
    final keyword = selection.keyword?.trim();
    final shouldReport = _emptySearchReporter.shouldReport(
      itemCount: async.valueOrNull?.items.length,
      keyword: keyword,
      broadened: selection.includeUnfollowed,
    );
    if (!shouldReport) return;
    unawaited(
      ref.read(analyticsServiceProvider).trackSearchSubmittedEmpty(
            queryLength: keyword!.length,
            broadened: selection.includeUnfollowed,
          ),
    );
  }

  /// État vide d'un filtre actif — story 30.1. Jusqu'ici Flâner rendait une
  /// liste vide (écran blanc) : c'était l'impasse la plus fréquente de la
  /// recherche.
  Widget _buildEmptyFilterState(
    FeedFilterSelection selection,
    FeedFilterKind kind, {
    bool compact = false,
  }) {
    final clear = ref.read(feedProvider.notifier).clearFilters;
    if (kind != FeedFilterKind.keyword) {
      return EmptyFilterState(
        kind: kind,
        filterName: _resolvedFilterLabel(),
        compact: compact,
        onClearFilter: clear,
      );
    }
    final keyword = selection.keyword!.trim();
    return EmptyFilterState(
      kind: kind,
      filterName: keyword,
      compact: compact,
      alreadyBroadened: selection.includeUnfollowed,
      onClearFilter: clear,
      onBroaden: () => _broadenSearch(keyword, 0),
      onSearchSource: () => openAddSourceFor(context, ref, keyword),
      onFollowTopic: () => followKeywordAsTopic(context, ref, keyword),
    );
  }

  /// Libellé lisible du filtre actif, quand on sait le résoudre localement —
  /// sinon `null`, et l'état vide garde son titre générique (mieux qu'un slug
  /// brut affiché à l'utilisateur). Réutilise [activeFilterLabelProvider]
  /// (source de vérité partagée avec le header et la barre de filtres) et
  /// n'affiche que les libellés `resolved`.
  String? _resolvedFilterLabel() {
    final active = ref.read(activeFilterLabelProvider);
    if (active == null || !active.resolved) return null;
    return active.label;
  }

  Widget _buildContent(BuildContext context, FeedState state) {
    final colors = context.facteurColors;
    final selection = ref.watch(feedFilterSelectionProvider);
    final activeKind = selection.activeKind;
    final keyword = selection.keyword?.trim();
    final hasKeyword = activeKind == FeedFilterKind.keyword;
    // Calculé avant l'état vide : afficher « Aucun article » en pleine page
    // au-dessus d'un bloc Explorer bien garni était une fausse impasse.
    final exploreSlivers = _buildExploreSlivers(state);
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
          const SliverToBoxAdapter(child: ChangelogBanner()),
          const SliverPersistentHeader(
            pinned: true,
            delegate: _FilterHeaderDelegate(child: _FilterSurface()),
          ),
          // Bandeau contextuel éphémère après une bascule Essentiel → Flâner
          // depuis la recherche du header : rappelle sur quoi on vient d'arriver
          // (« Résultats pour « … » ») le temps de se repérer, puis s'efface.
          const SliverToBoxAdapter(child: _SearchNavBanner()),
          const SliverToBoxAdapter(child: PinSubjectsBanner()),
          const SliverToBoxAdapter(child: WidgetCtaBanner()),
          // Recherche bredouille → l'état vide porte déjà « suivre ce sujet »
          // parmi ses rattrapages ; on n'empile pas deux invitations à suivre.
          if (hasKeyword && state.items.isNotEmpty)
            SliverToBoxAdapter(
              child: FollowKeywordSuggestionCard(keyword: keyword!),
            ),
          // Récolte maigre → on propose d'élargir plutôt que de laisser
          // l'utilisateur conclure « il n'y a rien ». Le périmètre par défaut
          // (sources suivies) reste le bon, mais il doit être franchissable.
          if (hasKeyword &&
              !selection.includeUnfollowed &&
              state.items.isNotEmpty &&
              state.items.length < 5)
            SliverToBoxAdapter(
              child: _BroadenSearchBanner(
                resultCount: state.items.length,
                onBroaden: () => _broadenSearch(keyword!, state.items.length),
              ),
            ),
          if (state.items.length > 4)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: PepitesCarousel(),
              ),
            ),
          if (state.items.isEmpty && activeKind != null)
            SliverToBoxAdapter(
              child: _buildEmptyFilterState(
                selection,
                activeKind,
                compact: exploreSlivers.isNotEmpty,
              ),
            )
          else
            _buildFeedList(state),
          if (_loadingMore)
            const SliverToBoxAdapter(child: _LoadingMoreIndicator()),
          ...exploreSlivers,
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
    final firstSwipeableIndex = contents.indexWhere(
      (article) => !_pendingFeedback.contains(article.id),
    );
    if (firstSwipeableIndex >= 0) {
      _scheduleGestureNudge();
    }

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
        if (_pendingFeedback.contains(article.id)) {
          return _feedbackInline(article);
        }
        return VisibilityDetector(
          key: ValueKey('flaner_visible_${article.id}'),
          onVisibilityChanged: (info) {
            if (info.visibleFraction >= 0.9) _markVisible(article.id);
          },
          child: FluxContinuArticleCard(
            key: ValueKey('flaner_card_${article.id}'),
            article: article,
            onTap: () => _openArticle(article),
            onSwipeDismiss: () => _onSwipeDismiss(article),
            enableSwipeHint:
                articleIndex == firstSwipeableIndex && _showSwipeHint,
            onSwipeHintComplete: _onSwipeHintComplete,
            nudgeAnchor:
                articleIndex == firstSwipeableIndex ? flanerFirstCardKey : null,
            onSwipeConversion: _recordSwipeConversion,
            onLongPressConversion: _recordLongPressConversion,
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
            delegate: SliverChildBuilderDelegate((context, index) {
              final article = discovery[index];
              return FluxContinuArticleCard(
                article: article,
                onTap: () => _openArticle(article),
              );
            }, childCount: discovery.length),
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

/// Bandeau « récolte maigre » — propose d'élargir la recherche mot-clé aux
/// sources non suivies (story 30.1). Discret : c'est une suggestion, pas une
/// erreur.
class _BroadenSearchBanner extends StatelessWidget {
  final int resultCount;
  final VoidCallback onBroaden;

  const _BroadenSearchBanner({
    required this.resultCount,
    required this.onBroaden,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FacteurSpacing.space4,
        FacteurSpacing.space1,
        FacteurSpacing.space4,
        FacteurSpacing.space2,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: FacteurSpacing.space3,
          vertical: FacteurSpacing.space2,
        ),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(FacteurRadius.medium),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                resultCount > 1
                    ? '$resultCount résultats dans tes sources'
                    : '1 seul résultat dans tes sources',
                style: FacteurTypography.bodySmall(colors.textSecondary),
              ),
            ),
            const SizedBox(width: FacteurSpacing.space2),
            TextButton(
              onPressed: onBroaden,
              style: TextButton.styleFrom(
                foregroundColor: colors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Élargir'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bandeau contextuel éphémère joué après une bascule Essentiel → Flâner
/// déclenchée par la recherche du header (story 30.1 pré-merge).
///
/// Auto-géré : il consomme **une fois** le signal [searchJustNavigatedProvider]
/// (armé par [HeaderSearchButton] avant le `go(flaner)`), affiche
/// « Résultats pour « … » » / « Filtré sur … » pendant ~3 s, puis se fond en
/// sortie. Il ne s'arme **jamais** quand le filtre change depuis la barre de
/// filtres de Flâner : l'utilisateur y est déjà.
///
/// Utilise `ref.listen` (et un contrôle du signal au montage) pour rester
/// robuste que Flâner soit déjà monté (IndexedStack) ou construit à la volée.
class _SearchNavBanner extends ConsumerStatefulWidget {
  const _SearchNavBanner();

  @override
  ConsumerState<_SearchNavBanner> createState() => _SearchNavBannerState();
}

class _SearchNavBannerState extends ConsumerState<_SearchNavBanner> {
  Timer? _timer;
  bool _visible = false;
  String? _text;

  @override
  void initState() {
    super.initState();
    // Cas « déjà monté et signal posé avant que le listener n'existe » : on
    // vérifie l'état courant au premier frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumeIfPending());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _consumeIfPending() {
    if (!mounted || !ref.read(searchJustNavigatedProvider)) return;
    // Éteint le signal : one-shot (idempotent avec le `ref.listen`).
    ref.read(searchJustNavigatedProvider.notifier).state = false;
    final text = _bannerText();
    if (text == null) return;
    setState(() {
      _text = text;
      _visible = true;
    });
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  String? _bannerText() {
    final active = ref.read(activeFilterLabelProvider);
    if (active == null) return null;
    if (active.isKeyword) {
      final selection = ref.read(feedFilterSelectionProvider);
      final keyword = selection.keyword?.trim();
      if (keyword == null || keyword.isEmpty) return null;
      final suffix = selection.includeUnfollowed ? ' · toutes sources' : '';
      return 'Résultats pour « $keyword »$suffix';
    }
    return 'Filtré sur ${active.label}';
  }

  @override
  Widget build(BuildContext context) {
    // Un nouveau signal (false → true) pendant que le widget est monté.
    ref.listen<bool>(searchJustNavigatedProvider, (prev, next) {
      if (next) _consumeIfPending();
    });

    final colors = context.facteurColors;
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: (!_visible || _text == null)
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.fromLTRB(
                  FacteurSpacing.space4,
                  FacteurSpacing.space2,
                  FacteurSpacing.space4,
                  FacteurSpacing.space1,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FacteurSpacing.space3,
                    vertical: FacteurSpacing.space2,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(FacteurRadius.medium),
                    border: Border.all(
                      color: colors.primary.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        PhosphorIcons.magnifyingGlass(PhosphorIconsStyle.bold),
                        size: 15,
                        color: colors.primary,
                      ),
                      const SizedBox(width: FacteurSpacing.space2),
                      Expanded(
                        child: Text(
                          _text!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FacteurTypography.bodySmall(colors.primary)
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
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
