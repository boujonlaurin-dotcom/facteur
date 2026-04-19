import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/theme.dart';
import '../../../config/topic_labels.dart';
import '../../../config/routes.dart';
import '../../../core/providers/analytics_provider.dart';
import '../../../core/providers/navigation_providers.dart';
import '../providers/feed_provider.dart';
import '../widgets/welcome_banner.dart';
import '../../../widgets/design/facteur_logo.dart';
import '../../../widgets/design/facteur_button.dart';
import '../models/content_model.dart';
import '../widgets/feed_card.dart';
import '../widgets/compact_source_chip.dart';
import '../widgets/compact_search_chip.dart';
import '../widgets/compact_theme_chip.dart';
import '../widgets/animated_feed_card.dart';
import '../widgets/caught_up_card.dart';
import '../widgets/swipe_to_open_card.dart';
import '../widgets/feedback_inline.dart';
import '../providers/swipe_hint_provider.dart';
import '../../../widgets/article_preview_modal.dart';
import '../../saved/widgets/collection_picker_sheet.dart';
import '../../saved/providers/collections_provider.dart';
import '../../saved/widgets/saved_nudge.dart';
import '../../saved/providers/saved_summary_provider.dart';
import '../../../core/ui/notification_service.dart';
import 'dart:math' as math;
import '../../gamification/providers/streak_provider.dart';
import '../../custom_topics/widgets/topic_chip.dart';
// DEADCODE: Feature "X autres articles" masquée
// import '../../custom_topics/widgets/cluster_chip.dart';
// import '../widgets/keyword_overflow_chip.dart';
// import '../widgets/entity_overflow_chip.dart';
import '../widgets/feed_carousel.dart';
import '../widgets/feed_refresh_undo_banner.dart';
import '../../custom_topics/providers/custom_topics_provider.dart';
import '../widgets/empty_filter_state.dart';
import '../widgets/follow_keyword_suggestion_card.dart';
import '../widgets/interest_filter_sheet.dart';
import '../../digest/providers/serein_toggle_provider.dart';
import '../../digest/widgets/serein_toggle_chip.dart';
import '../../sources/providers/sources_providers.dart';
import '../../progress/widgets/progression_card.dart';
import '../../../shared/widgets/mode_accent.dart';

/// Écran principal du feed
class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  bool _showWelcome = false;
  bool _caughtUpDismissed = false;
  static const int _caughtUpThreshold = 8;
  final ScrollController _scrollController = ScrollController();
  double _maxScrollPercent = 0.0;
  final int _itemsViewed = 0;

  bool _hasNudged = false;

  bool _swipeHintSeen = false;
  final double _lastScrollPosition = 0;

  // Feed Refresh: track timestamps of recent refreshes for anti-addiction
  final List<DateTime> _refreshTimestamps = [];

  // Dynamic progressions map: ContentID -> Topic
  final Map<String, String> _activeProgressions = {};

  // Feed loading state: true while any filter change or serein toggle refreshes
  bool _isFeedRefreshing = false;

  // Story 4.5b: Show the undo banner after a viewport-aware pull-to-refresh.
  bool _showUndoBanner = false;

  /// Articles swipe-dismissés en attente de feedback (rendus en banner inline
  /// à la place de la carte). Le hide API a déjà été appelé au moment du
  /// swipe ; la résolution (CTA, X, ou viewport-exit) déclenche
  /// `removeFromState` pour retirer l'item du provider.
  final Map<String, Content> _pendingFeedback = {};

  void _resolveFeedback(String contentId) {
    if (!mounted) return;
    if (!_pendingFeedback.containsKey(contentId)) return;
    setState(() => _pendingFeedback.remove(contentId));
    ref.read(feedProvider.notifier).removeFromState(contentId);
  }

  Future<void> _withFeedLoading(Future<void> Function() action) async {
    if (mounted) setState(() => _isFeedRefreshing = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _isFeedRefreshing = false);
    }
  }

  // Interest filter: store selected name & type to avoid re-derivation bugs
  String? _selectedInterestName;
  bool _selectedIsTheme = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _showChronoMigrationToast();
  }

  // Epic 12: One-shot toast explaining the new chronological default
  Future<void> _showChronoMigrationToast() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('chrono_feed_migration_seen') ?? false;
    if (!seen && mounted) {
      await prefs.setBool('chrono_feed_migration_seen', true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Votre flux est maintenant chronologique. '
            'Retrouvez l\'ancien tri dans "Pour vous".',
          ),
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  // Story 4.5b: Track IDs of articles that have been "fully visible" (≥ 0.9
  // viewport fraction) since the last refresh. Includes both main feed cards
  // AND items from carousels. Used by pull-to-refresh to mark these articles
  // as "already impressed" so the backend scoring layer demotes them.
  final Set<String> _fullyVisibleIds = {};

  Future<void> _showArticleModal(Content content) async {
    // 1. Mark as consumed immediately
    if (mounted) {
      ref.read(feedProvider.notifier).markContentAsConsumed(content);

      // Capture the notifier *now* while `ref` is guaranteed valid; using
      // `ref.read` inside a delayed callback can throw
      // "Cannot use 'ref' after the widget was disposed" if the user leaves
      // the feed before the delay elapses.
      final streakNotifier = ref.read(streakProvider.notifier);
      Future<void>.delayed(const Duration(milliseconds: 1100), () {
        if (mounted) {
          streakNotifier.refreshSilent();
        }
      });
    }

    // 2. Premium source → open in external browser for authenticated access
    final sources = ref.read(userSourcesProvider).valueOrNull ?? [];
    final isPremium =
        sources.any((s) => s.id == content.source.id && s.hasSubscription);
    if (isPremium && content.url.isNotEmpty) {
      final uri = Uri.tryParse(content.url);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }

    // 3. Navigation
    if (!kIsWeb &&
        (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      launchUrl(Uri.parse(content.url));
      return;
    }

    final updated = await context.push<Content?>(
      '/feed/content/${content.id}',
      extra: content,
    );
    if (updated != null) {
      ref.read(feedProvider.notifier).updateContent(updated);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uri = GoRouterState.of(context).uri;
    if (uri.queryParameters['welcome'] == 'true' && !_showWelcome) {
      setState(() {
        _showWelcome = true;
      });
    }
  }

  @override
  void dispose() {
    // Track analytics before disposing controller
    // Note: ref may not be available during dispose in Riverpod, so we catch any errors
    try {
      // Only track if we have valid data and ref is still available
      if (_itemsViewed > 0) {
        final analytics = ref.read(analyticsServiceProvider);
        analytics.trackFeedScroll(_maxScrollPercent, _itemsViewed);
      }
    } catch (e) {
      // Silently ignore ref errors during dispose - widget is being cleaned up
      debugPrint('FeedScreen: Analytics tracking skipped during dispose');
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;

    // Analytics
    if (maxScroll > 0) {
      final percent = (currentScroll / maxScroll).clamp(0.0, 1.0);
      if (percent > _maxScrollPercent) {
        _maxScrollPercent = percent;
      }
    }

    // Story 4.5b: Viewport tracking is now handled by VisibilityDetector
    // wrapping each feed card + carousel item. _fullyVisibleIds is populated
    // via onVisibilityChanged callbacks (threshold ≥ 0.9).

    // Load more — skip when user is actively scrolling UP.
    // Triggering a state update + SliverList rebuild during an upward scroll
    // causes Flutter to recalculate scroll geometry mid-gesture, which snaps
    // the position back to the bottom. Only block when direction is explicitly
    // forward (= toward top); idle and reverse (toward bottom) are fine.
    final notScrollingUp = _scrollController.position.userScrollDirection !=
        ScrollDirection.forward;
    if (currentScroll >= maxScroll - 800 && notScrollingUp) {
      ref.read(feedProvider.notifier).loadMore();
    }
  }

  /// Animation déclenchée après un clic sur une balise de thème/source/entité
  /// (depuis le feed lui-même OU depuis le reader d'article via
  /// `feedScrollTriggerProvider`). Volontairement longue + courbe en S pour
  /// que l'utilisateur perçoive clairement la transition vers le feed filtré.
  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  void _dismissWelcome() {
    setState(() {
      _showWelcome = false;
    });
    context.go(RoutePaths.feed);
  }

  bool get _isRefreshCompulsive {
    // 3+ refreshes in 10 minutes → suggest "Articles récents" mode
    final cutoff = DateTime.now().subtract(const Duration(minutes: 10));
    final recent = _refreshTimestamps.where((t) => t.isAfter(cutoff)).length;
    return recent >= 3;
  }

  /// Story 4.5b: Pull-to-refresh viewport-aware.
  ///
  /// - Marque tous les articles pleinement visibles (main feed + carrousels)
  ///   comme "déjà vus" via POST /feed/refresh.
  /// - Capture un snapshot pour l'undo et affiche un bandeau discret.
  /// - Anti-addiction : 3+ refreshes en 10 min → modal "Rester serein".
  /// - Parité web/native.
  Future<void> _refresh() async {
    // Anti-addiction check: only show modal when user is compulsive
    if (_isRefreshCompulsive && !kIsWeb) {
      final colors = context.facteurColors;
      final result = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (ctx) => _RefreshConfirmSheet(
          isCompulsive: true,
          colors: colors,
        ),
      );

      if (result == 'serein') {
        ref.read(feedProvider.notifier).setFilter('inspiration');
        return;
      }
      if (result != 'refresh') {
        return; // User dismissed
      }
      // Fall through to refresh action
    }

    _refreshTimestamps.add(DateTime.now());

    // Snapshot the currently fully-visible IDs and clear the tracker so the
    // next refresh starts from scratch.
    final visibleIds = Set<String>.from(_fullyVisibleIds);
    _fullyVisibleIds.clear();

    await ref
        .read(feedProvider.notifier)
        .refreshArticlesWithSnapshot(visibleIds);

    // Scroll-to-top (convention pull-to-refresh).
    if (mounted && _scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }

    // Show undo banner if a snapshot was captured (otherwise no meaningful undo).
    final snapshot = ref.read(feedUndoSnapshotProvider);
    if (snapshot != null && mounted) {
      HapticFeedback.selectionClick();
      setState(() => _showUndoBanner = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final feedAsync = ref.watch(feedProvider);
    final colors = context.facteurColors;

    // Pre-warm topics provider (single watch for all TopicChips)
    final followedTopics = ref.watch(customTopicsProvider).valueOrNull ?? [];

    // Swipe-left hint: check if already seen
    final hintSeen = ref.watch(swipeLeftHintSeenProvider).valueOrNull ?? false;
    if (hintSeen) _swipeHintSeen = true;

    // Listen to scroll to top trigger.
    // Quand l'utilisateur clique sur une balise depuis le reader d'un article,
    // on attend que la transition de page (Cupertino slide-back) soit bien
    // entamée avant de scroller, sinon le scroll est masqué par l'écran
    // article qui glisse encore par-dessus le feed.
    // Utilise Timer (et non Future.delayed) pour éviter un unawaited future.
    ref.listen(feedScrollTriggerProvider, (_, __) {
      Timer(const Duration(milliseconds: 220), () {
        if (mounted) _scrollToTop();
      });
    });

    // Serein toggle: loading indicator tied to actual feed refresh
    ref.listen(sereinToggleProvider.select((s) => s.enabled), (prev, next) {
      if (prev != next && mounted) {
        _withFeedLoading(() => ref.read(feedProvider.notifier).refresh());
      }
    });

    return PopScope(
      canPop: false,
      child: Material(
        color: colors.backgroundPrimary,
        child: Stack(
          children: [
            SafeArea(
              child: RefreshIndicator(
                onRefresh: _refresh,
                color: colors.primary,
                child: CustomScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: FacteurSpacing.space6,
                          vertical: FacteurSpacing.space3,
                        ),
                        child: Center(child: FacteurLogo(size: 22, showIcon: false)),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 16, 8, 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Bonjour,',
                                style: Theme.of(context)
                                    .textTheme
                                    .displayMedium,
                              ),
                            ),
                            const SereinToggleChip(),
                          ],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          'Votre flux issu de vos sources de confiance.',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: colors.textSecondary),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16.0, vertical: 8.0),
                        child: Builder(builder: (context) {
                          final notifier = ref.read(feedProvider.notifier);

                          // Sync local display state with notifier — reset if no filter active
                          if (notifier.selectedTheme == null &&
                              notifier.selectedTopic == null &&
                              notifier.selectedEntity == null) {
                            _selectedInterestName = null;
                            _selectedIsTheme = false;
                          }

                          // Source filter state
                          final sourcesAsync = ref.watch(userSourcesProvider);
                          final allSources = sourcesAsync.valueOrNull ?? [];
                          final followedSources = allSources
                              .where((s) =>
                                  (s.isTrusted || s.isCustom) && !s.isMuted)
                              .toList();
                          final selectedSourceId = notifier.selectedSourceId;
                          final selectedSourceName = selectedSourceId != null
                              ? followedSources
                                  .where((s) => s.id == selectedSourceId)
                                  .firstOrNull
                                  ?.name
                              : null;
                          final selectedSourceLogoUrl = selectedSourceId != null
                              ? followedSources
                                  .where((s) => s.id == selectedSourceId)
                                  .firstOrNull
                                  ?.logoUrl
                              : null;

                          // Interest filter state
                          final customTopics =
                              ref.watch(customTopicsProvider).valueOrNull ?? [];

                          return Row(
                            children: [
                              Flexible(
                                child: CompactSourceChip(
                                  followedSources: followedSources,
                                  selectedSourceId: selectedSourceId,
                                  selectedSourceName: selectedSourceName,
                                  selectedSourceLogoUrl: selectedSourceLogoUrl,
                                  onSourceChanged: (sourceId) {
                                    if (sourceId != null) {
                                      _withFeedLoading(
                                          () => notifier.setSource(sourceId));
                                    } else {
                                      notifier.setSource(null);
                                    }
                                    _scrollToTop();
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: CompactThemeChip(
                                  followedTopics: customTopics,
                                  selectedSlug: notifier.selectedTopic ??
                                      notifier.selectedTheme ??
                                      notifier.selectedEntity,
                                  selectedName: _selectedInterestName,
                                  selectedIsTheme: _selectedIsTheme,
                                  onInterestChanged: (slug, name,
                                      {isTheme = false, isEntity = false}) {
                                    setState(() {
                                      _selectedInterestName = name;
                                      _selectedIsTheme = isTheme;
                                    });
                                    _withFeedLoading(() async {
                                      if (slug == null) {
                                        await notifier.setTopic(null);
                                        await notifier.setTheme(null);
                                        await notifier.setEntity(null);
                                      } else if (isTheme) {
                                        await notifier.setTheme(slug);
                                      } else if (isEntity) {
                                        await notifier.setEntity(slug);
                                      } else {
                                        await notifier.setTopic(slug);
                                      }
                                    });
                                    _scrollToTop();
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: CompactSearchChip(
                                  activeKeyword: notifier.selectedKeyword,
                                  onSearchChanged: (keyword,
                                      {bool fromTrending = false}) {
                                    _withFeedLoading(() => notifier.setKeyword(
                                          keyword,
                                          includeUnfollowed: fromTrending,
                                        ));
                                    _scrollToTop();
                                  },
                                ),
                              ),
                            ],
                          );
                        }),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Consumer(builder: (context, ref, _) {
                        final keyword =
                            ref.watch(feedProvider.notifier).selectedKeyword;
                        if (keyword == null || keyword.trim().isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return FollowKeywordSuggestionCard(keyword: keyword);
                      }),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 16)),
                    // Brief loading indicator when serein toggle triggers feed refresh
                    if (_isFeedRefreshing)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              minHeight: 2,
                              backgroundColor: colors.border,
                              color: colors.primary,
                            ),
                          ),
                        ),
                      ),
                    feedAsync.when(
                      data: (state) {
                        final contents = state.items;
                        final notifier = ref.read(feedProvider.notifier);

                        final subscribedSources =
                            ref.watch(userSourcesProvider).valueOrNull ?? [];
                        final subscribedSourceIds = subscribedSources
                            .where((s) => s.hasSubscription)
                            .map((s) => s.id)
                            .toSet();

                        final streakAsync = ref.watch(streakProvider);
                        final dailyCount =
                            streakAsync.valueOrNull?.weeklyCount ?? 0;
                        final showCaughtUp = dailyCount >= _caughtUpThreshold &&
                            !_caughtUpDismissed;
                        // Position de la carte "Tu es à jour" après 8 articles
                        const caughtUpPos = 8;

                        // Saved nudge: show at position 6 if user has 3+ unread saves
                        final savedSummary =
                            ref.watch(savedSummaryProvider).valueOrNull;
                        final savedNudgeDismissed = ref
                                .watch(savedNudgeDismissedProvider)
                                .valueOrNull ??
                            false;
                        final showSavedNudge = !showCaughtUp &&
                            !savedNudgeDismissed &&
                            savedSummary != null &&
                            savedSummary.unreadCount >= 3 &&
                            contents.length > 6;
                        const savedNudgePos = 6;

                        // Empty state when a filter is active but no results
                        final hasActiveFilter =
                            notifier.selectedTheme != null ||
                                notifier.selectedTopic != null ||
                                notifier.selectedEntity != null ||
                                notifier.selectedSourceId != null;

                        // Carousels: sorted by position, hidden when filter active
                        final sortedCarousels = hasActiveFilter
                            ? <FeedCarouselData>[]
                            : ([...state.carousels]
                                .where((c) => c.items.isNotEmpty)
                                .toList()
                                ..sort((a, b) => a.position.compareTo(b.position)));

                        // childCount calculé dynamiquement pour garantir exactement 1 slot
                        // trailing (loader ou spacer). CaughtUp et SavedNudge sont
                        // mutuellement exclusifs → intercalatedCount ≤ 1.
                        final int intercalatedCount =
                            (showCaughtUp ? 1 : 0) + (showSavedNudge ? 1 : 0) + sortedCarousels.length;
                        final int effectiveChildCount =
                            contents.isEmpty ? 1 : contents.length + intercalatedCount + 1;

                        if (contents.isEmpty && hasActiveFilter) {
                          // Resolve source name from ID for display
                          final sourceFilterName = notifier.selectedSourceId != null
                              ? (ref.read(userSourcesProvider).valueOrNull ?? [])
                                  .where((s) => s.id == notifier.selectedSourceId)
                                  .firstOrNull
                                  ?.name
                              : null;

                          return SliverToBoxAdapter(
                            child: EmptyFilterState(
                              filterName: _selectedInterestName ??
                                  sourceFilterName,
                              isTheme: notifier.selectedTheme != null,
                              isEntity: notifier.selectedEntity != null,
                              isSource: notifier.selectedSourceId != null,
                              onClearFilter: () {
                                setState(() {
                                  _selectedInterestName = null;
                                  _selectedIsTheme = false;
                                });
                                notifier.setTopic(null);
                                notifier.setTheme(null);
                                notifier.setEntity(null);
                                notifier.setSource(null);
                                notifier.setFilter(null);
                              },
                              onBrowseThemes: () {
                                InterestFilterSheet.show(
                                  context,
                                  currentTopicSlug: null,
                                  onInterestSelected: (slug, name, {bool isTheme = false, bool isEntity = false}) {
                                    setState(() {
                                      _selectedInterestName = name;
                                      _selectedIsTheme = isTheme;
                                    });
                                    if (isTheme) {
                                      notifier.setTheme(slug);
                                    } else {
                                      notifier.setTopic(slug);
                                    }
                                  },
                                );
                              },
                            ),
                          );
                        }

                        return SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          sliver: SliverAnimatedOpacity(
                            opacity: _isFeedRefreshing ? 0.3 : 1.0,
                            duration: const Duration(milliseconds: 200),
                            sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final listIndex = index;

                                // Interleaving logic - calculer l'offset pour les éléments intercalés
                                int contentOffset = 0;

                                // Caught up card - s'affiche après caughtUpPos articles
                                if (showCaughtUp) {
                                  if (listIndex == caughtUpPos) {
                                    return Padding(
                                        key: const ValueKey('caught_up_card'),
                                        padding:
                                            const EdgeInsets.only(bottom: 16),
                                        child: CaughtUpCard(onDismiss: () {
                                          setState(
                                              () => _caughtUpDismissed = true);
                                          // Forcer le chargement de plus d'articles
                                          ref
                                              .read(feedProvider.notifier)
                                              .loadMore();
                                        }));
                                  }
                                  // Avant la carte : continuer normalement
                                }

                                // Compter la CaughtUpCard si elle est passée (pour le décalage)
                                if (showCaughtUp && listIndex > caughtUpPos) {
                                  contentOffset++;
                                }

                                // Saved Nudge at position 6
                                if (showSavedNudge) {
                                  final savedNudgeEffectivePos =
                                      savedNudgePos + contentOffset;
                                  if (listIndex == savedNudgeEffectivePos) {
                                    final count = savedSummary.unreadCount;
                                    return SavedNudge(
                                      key: const ValueKey('saved_nudge'),
                                      message:
                                          'Tu as $count article${count > 1 ? 's' : ''} sauvegardé${count > 1 ? 's' : ''} non lu${count > 1 ? 's' : ''}',
                                    );
                                  }
                                  if (listIndex > savedNudgeEffectivePos) {
                                    contentOffset++;
                                  }
                                }

                                // Carousels at their designated positions
                                for (final carousel in sortedCarousels) {
                                  final effectivePos = carousel.position.clamp(0, contents.length) + contentOffset;
                                  if (listIndex == effectivePos) {
                                    contentOffset++;
                                    return Padding(
                                      key: ValueKey('carousel_${carousel.carouselType}'),
                                      padding: const EdgeInsets.only(bottom: 16),
                                      child: FeedCarousel(
                                        data: carousel,
                                        onArticleTap: (c) => _showArticleModal(c),
                                        // Story 4.5b: viewport-aware refresh.
                                        onItemVisible: (id) =>
                                            _fullyVisibleIds.add(id),
                                        // T1: Full card feature parity
                                        onLongPressStart: (c, _) =>
                                            ArticlePreviewOverlay.show(context, c),
                                        onLongPressMoveUpdate: (details) =>
                                            ArticlePreviewOverlay.updateScroll(
                                                details.localOffsetFromOrigin.dy),
                                        onLongPressEnd: (_) =>
                                            ArticlePreviewOverlay.dismiss(),
                                        onLike: (c) {
                                          final wasLiked = c.isLiked;
                                          ref.read(feedProvider.notifier).toggleLike(c);
                                          NotificationService.showInfo(
                                            wasLiked
                                                ? 'Retiré de Mes contenus recommandés 🌻'
                                                : 'Ajouté à Mes contenus recommandés 🌻',
                                          );
                                          ref.invalidate(collectionsProvider);
                                        },
                                        onSave: (c) async {
                                          final wasSaved = c.isSaved;
                                          ref.read(feedProvider.notifier).toggleSave(c);
                                          if (!wasSaved) {
                                            final defaultCol =
                                                ref.read(defaultCollectionProvider);
                                            if (defaultCol != null) {
                                              final colRepo = ref
                                                  .read(collectionsRepositoryProvider);
                                              await colRepo.addToCollection(
                                                  defaultCol.id, c.id);
                                              ref.invalidate(collectionsProvider);
                                            }
                                            if (context.mounted) {
                                              CollectionPickerSheet.show(
                                                  context, c.id);
                                            }
                                          }
                                        },
                                        onSaveLongPress: (c) =>
                                            CollectionPickerSheet.show(context, c.id),
                                        onSourceTap: (sourceId) {
                                          ref
                                              .read(feedProvider.notifier)
                                              .setSource(sourceId);
                                          _scrollToTop();
                                        },
                                        onSourceLongPress: (c) =>
                                            TopicChip.showArticleSheet(context, c,
                                                initialSection:
                                                    ArticleSheetSection.source),
                                        topicChipBuilder: (c) => TopicChip(
                                          content: c,
                                          isFollowed: c.topics.isNotEmpty &&
                                              followedTopics.any((t) =>
                                                  t.slugParent == c.topics.first ||
                                                  t.name.toLowerCase() ==
                                                      getTopicLabel(c.topics.first)
                                                          .toLowerCase()),
                                          onTap: c.topics.isNotEmpty
                                              ? () {
                                                  final slug = c.topics.first;
                                                  setState(() {
                                                    _selectedInterestName =
                                                        getTopicLabel(slug);
                                                    _selectedIsTheme = false;
                                                  });
                                                  ref
                                                      .read(feedProvider.notifier)
                                                      .setTopic(slug);
                                                  _scrollToTop();
                                                }
                                              : null,
                                        ),
                                        onFollowSource: (c) =>
                                            TopicChip.showArticleSheet(context, c),
                                        subscribedSourceIds: subscribedSourceIds,
                                        hasActiveFilter: hasActiveFilter,
                                        isSerene:
                                            ref.watch(sereinToggleProvider).enabled,
                                        onReportNotSerene: (c) async {
                                          HapticFeedback.lightImpact();
                                          try {
                                            final feedRepo =
                                                ref.read(feedRepositoryProvider);
                                            await feedRepo.reportNotSerene(c.id);
                                            NotificationService.showSuccess(
                                                'Merci, nous en prenons note');
                                          } catch (e) {
                                            NotificationService.showError(
                                                'Erreur lors du signalement');
                                          }
                                        },
                                      ),
                                    );
                                  }
                                  if (listIndex > effectivePos) {
                                    contentOffset++;
                                  }
                                }

                                final contentIndex = listIndex - contentOffset;

                                if (contentIndex >= contents.length) {
                                  if (ref.read(feedProvider.notifier).hasNext) {
                                    return const Center(
                                        child: Padding(
                                            padding: EdgeInsets.all(16.0),
                                            child: CircularProgressIndicator
                                                .adaptive()));
                                  }
                                  return const SizedBox(height: 64);
                                }

                                if (contentIndex < 0) {
                                  return const SizedBox.shrink();
                                }

                                final content = contents[contentIndex];

                                // Carte swipe-dismissée → remplacée par le
                                // banner inline de feedback, à la même position.
                                // Hide API a déjà été appelé (au swipe).
                                // Résolution = CTA, X, ou viewport-exit.
                                if (_pendingFeedback.containsKey(content.id)) {
                                  return Padding(
                                    key: ValueKey('feedback_${content.id}'),
                                    padding:
                                        const EdgeInsets.only(bottom: 16),
                                    child: VisibilityDetector(
                                      key: Key('feedback_vis_${content.id}'),
                                      onVisibilityChanged: (info) {
                                        if (info.visibleFraction == 0) {
                                          _resolveFeedback(content.id);
                                        }
                                      },
                                      child: FeedbackInline(
                                        onSelectSource: () async {
                                          await TopicChip.showArticleSheet(
                                            context,
                                            content,
                                            initialSection:
                                                ArticleSheetSection.source,
                                            highlightInitialSection: true,
                                          );
                                          _resolveFeedback(content.id);
                                        },
                                        onSelectTopic: () async {
                                          await TopicChip.showArticleSheet(
                                            context,
                                            content,
                                            initialSection:
                                                ArticleSheetSection.topic,
                                            highlightInitialSection: true,
                                          );
                                          _resolveFeedback(content.id);
                                        },
                                        onSelectAlreadySeen: () =>
                                            _resolveFeedback(content.id),
                                        onUndo: () {
                                          // Re-surface la carte : annule
                                          // le hide côté backend et retire
                                          // simplement l'entrée pending
                                          // (l'item est toujours dans
                                          // state.items, donc la FeedCard
                                          // reprendra sa place).
                                          unawaited(ref
                                              .read(feedRepositoryProvider)
                                              .unhideContent(content.id)
                                              .catchError((Object e) {
                                            // ignore: avoid_print
                                            print(
                                                'FeedScreen: unhideContent failed for ${content.id}: $e');
                                          }));
                                          setState(() => _pendingFeedback
                                              .remove(content.id));
                                        },
                                        onClose: () =>
                                            _resolveFeedback(content.id),
                                      ),
                                    ),
                                  );
                                }

                                final isConsumed = ref
                                    .read(feedProvider.notifier)
                                    .isContentConsumed(content.id);
                                final progressionTopic =
                                    _activeProgressions[content.id];

                                final showHint =
                                    !_swipeHintSeen && contentIndex <= 1;

                                Widget cardWidget = SwipeToOpenCard(
                                  onSwipeOpen: () => _showArticleModal(content),
                                  onSwipeDismiss: () {
                                    // Hide API immédiat — le swipe est
                                    // l'engagement. Silent failure : l'inline
                                    // reste affiché même si le réseau échoue
                                    // (le user peut juste re-tap pour résoudre).
                                    unawaited(ref
                                        .read(feedRepositoryProvider)
                                        .hideContent(content.id)
                                        .catchError((Object e) {
                                      // ignore: avoid_print
                                      print(
                                          'FeedScreen: hideContent failed for ${content.id}: $e');
                                    }));
                                    setState(() =>
                                        _pendingFeedback[content.id] = content);
                                  },
                                  enableHintAnimation: showHint,
                                  onHintAnimationComplete: () {
                                    if (!_swipeHintSeen) {
                                      _swipeHintSeen = true;
                                      markSwipeLeftHintSeen();
                                      ref.invalidate(swipeLeftHintSeenProvider);
                                    }
                                  },
                                  child: AnimatedFeedCard(
                                    isConsumed: isConsumed,
                                    child: FeedCard(
                                      content: content,
                                      titleMaxLines: 5,
                                      onTap: () => _showArticleModal(content),
                                      onLongPressStart: (_) =>
                                          ArticlePreviewOverlay.show(
                                        context,
                                        content,
                                      ),
                                      onLongPressMoveUpdate: (details) =>
                                          ArticlePreviewOverlay.updateScroll(
                                        details.localOffsetFromOrigin.dy,
                                      ),
                                      onLongPressEnd: (_) =>
                                          ArticlePreviewOverlay.dismiss(),
                                      onLike: () {
                                        final wasLiked = content.isLiked;
                                        ref
                                            .read(feedProvider.notifier)
                                            .toggleLike(content);
                                        NotificationService.showInfo(
                                          wasLiked
                                              ? 'Retiré de Mes contenus recommandés 🌻'
                                              : 'Ajouté à Mes contenus recommandés 🌻',
                                        );
                                        ref.invalidate(collectionsProvider);
                                      },
                                      isLiked: content.isLiked,
                                      onSave: () async {
                                        final wasSaved = content.isSaved;
                                        ref
                                            .read(feedProvider.notifier)
                                            .toggleSave(content);
                                        if (!wasSaved) {
                                          // Auto-add to default collection
                                          final defaultCol = ref
                                              .read(defaultCollectionProvider);
                                          if (defaultCol != null) {
                                            final colRepo = ref.read(
                                                collectionsRepositoryProvider);
                                            await colRepo.addToCollection(
                                                defaultCol.id, content.id);
                                            ref.invalidate(collectionsProvider);
                                          }
                                          if (context.mounted) {
                                            CollectionPickerSheet.show(
                                                context, content.id);
                                          }
                                        }
                                      },
                                      isSaved: content.isSaved,
                                      onSaveLongPress: () =>
                                          CollectionPickerSheet.show(
                                              context, content.id),
                                      topicChipWidget: TopicChip(
                                        content: content,
                                        isFollowed: content
                                                .topics.isNotEmpty &&
                                            followedTopics.any((t) =>
                                                t.slugParent ==
                                                    content
                                                        .topics.first ||
                                                t.name.toLowerCase() ==
                                                    getTopicLabel(content
                                                            .topics.first)
                                                        .toLowerCase()),
                                        onTap: content.topics.isNotEmpty
                                            ? () {
                                                final slug = content.topics.first;
                                                setState(() {
                                                  _selectedInterestName = getTopicLabel(slug);
                                                  _selectedIsTheme = false;
                                                });
                                                ref.read(feedProvider.notifier).setTopic(slug);
                                                _scrollToTop();
                                              }
                                            : null,
                                      ),
                                      // DEADCODE: Bloc masqué temporairement (cluster/overflow chips)
                                      /*
                                      clusterChipWidget:
                                          // Suppress overflow chips when filter is active
                                          // (diversification is bypassed server-side)
                                          (notifier.selectedTheme != null ||
                                                  notifier.selectedTopic != null ||
                                                  notifier.selectedEntity != null ||
                                                  notifier.selectedSourceId != null ||
                                                  notifier.selectedKeyword != null)
                                              ? const SizedBox.shrink()
                                              : content.clusterHiddenCount > 0
                                                  ? ClusterChip(content: content)
                                                  : content.entityOverflowCount >= 4
                                                      ? EntityOverflowChip(
                                                          content: content,
                                                          onOverflowTap: (key, label) {
                                                            final name = label.split(' \u2014 ').first;
                                                            setState(() {
                                                              _selectedInterestName = name;
                                                              _selectedIsTheme = false;
                                                            });
                                                            _withFeedLoading(() => notifier.setEntity(key));
                                                            _scrollToTop();
                                                          },
                                                        )
                                                      : content.keywordOverflowCount >= 4
                                                          ? KeywordOverflowChip(content: content, onOverflowTap: _scrollToTop)
                                                          : const SizedBox.shrink(),
                                      */
                                      isFollowedSource: content.isFollowedSource,
                                      isSourceSubscribed: subscribedSourceIds
                                          .contains(content.source.id),
                                      hasActiveFilter: notifier.selectedTheme != null ||
                                          notifier.selectedTopic != null ||
                                          notifier.selectedEntity != null,
                                      onFollowSource: !content.isFollowedSource
                                          ? () {
                                              TopicChip.showArticleSheet(context, content);
                                            }
                                          : null,
                                      onSourceTap: () {
                                        ref.read(feedProvider.notifier).setSource(content.source.id);
                                        _scrollToTop();
                                      },
                                      onSourceLongPress: () =>
                                          TopicChip.showArticleSheet(context, content,
                                              initialSection: ArticleSheetSection.source),
                                      isSerene: ref.watch(sereinToggleProvider).enabled,
                                      onReportNotSerene: () async {
                                        HapticFeedback.lightImpact();
                                        try {
                                          final feedRepo = ref.read(feedRepositoryProvider);
                                          await feedRepo.reportNotSerene(content.id);
                                          NotificationService.showSuccess(
                                              'Merci, nous en prenons note');
                                        } catch (e) {
                                          NotificationService.showError(
                                              'Erreur lors du signalement');
                                        }
                                      },
                                    ),
                                  ),
                                );

                                // Nudge: subtle scale pulse on first card
                                if (contentIndex == 0 && !_hasNudged) {
                                  cardWidget = _NudgePulseWrapper(
                                    onComplete: () =>
                                        setState(() => _hasNudged = true),
                                    child: cardWidget,
                                  );
                                }

                                return VisibilityDetector(
                                  key: ValueKey('vis_${content.id}'),
                                  onVisibilityChanged: (info) {
                                    // Story 4.5b: track cards fully visible in
                                    // the viewport (>= 90%) so pull-to-refresh
                                    // can mark them as "already seen".
                                    if (info.visibleFraction >= 0.9) {
                                      _fullyVisibleIds.add(content.id);
                                    }
                                  },
                                  child: Padding(
                                  key: ValueKey(content.id),
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      cardWidget,
                                      if (progressionTopic != null) ...[
                                        TweenAnimationBuilder<double>(
                                          tween: Tween(begin: 0.0, end: 1.0),
                                          duration:
                                              const Duration(milliseconds: 500),
                                          curve: Curves.easeOutBack,
                                          builder: (context, value, child) {
                                            return Transform.scale(
                                              scale: value,
                                              child: Opacity(
                                                  opacity: value, child: child),
                                            );
                                          },
                                          child: ProgressionCard(
                                            topic: progressionTopic,
                                            onDismiss: () {
                                              setState(() {
                                                _activeProgressions
                                                    .remove(content.id);
                                              });
                                            },
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  ),
                                );
                              },
                              childCount: effectiveChildCount,
                              addAutomaticKeepAlives: false,
                              addRepaintBoundaries: true,
                            ),
                          ),
                          ),
                        );
                      },
                      loading: () => SliverToBoxAdapter(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: CircularProgressIndicator(
                              color: colors.primary,
                            ),
                          ),
                        ),
                      ),
                      error: (err, stack) => SliverToBoxAdapter(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                Icon(
                                    PhosphorIcons.warning(
                                        PhosphorIconsStyle.duotone),
                                    size: 48,
                                    color: colors.error),
                                const SizedBox(height: 16),
                                Text('Erreur de chargement',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                                Text(err.toString(),
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: colors.error)),
                                const SizedBox(height: 16),
                                FacteurButton(
                                    label: 'Réessayer',
                                    icon: PhosphorIcons.arrowClockwise(
                                        PhosphorIconsStyle.bold),
                                    onPressed: () => ref.refresh(feedProvider)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: ModeAccent(
                  isSerein: ref.watch(sereinToggleProvider).enabled,
                ),
              ),
            ),
            if (_showWelcome)
              Positioned.fill(
                child: SafeArea(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: WelcomeBanner(
                      onDismiss: _dismissWelcome,
                      secondaryMessage: null,
                    ),
                  ),
                ),
              ),
            // Story 4.5b: discreet undo banner after viewport-aware refresh.
            // Suppressed while WelcomeBanner is showing to avoid top-stack overlap.
            if (_showUndoBanner && !_showWelcome)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: FeedRefreshUndoBanner(
                      onUndo: () async {
                        await ref
                            .read(feedProvider.notifier)
                            .undoLastRefresh();
                      },
                      onAutoResolve: () {
                        // Confirm the refresh: drop the undo snapshot so a
                        // later empty-path refresh can't resurrect it.
                        ref
                            .read(feedUndoSnapshotProvider.notifier)
                            .state = null;
                        if (mounted) {
                          setState(() => _showUndoBanner = false);
                        }
                      },
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Subtle scale pulse to hint at long-press functionality.
/// Plays once after a short delay, then calls [onComplete].
class _NudgePulseWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback onComplete;

  const _NudgePulseWrapper({
    required this.child,
    required this.onComplete,
  });

  @override
  State<_NudgePulseWrapper> createState() => _NudgePulseWrapperState();
}

class _NudgePulseWrapperState extends State<_NudgePulseWrapper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onComplete();
      }
    });
    // Start after a short delay so the card is visible first
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted && !_started) {
        _started = true;
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = 1.0 + 0.04 * math.sin(_controller.value * 2 * math.pi);
        return Transform.scale(scale: scale, child: child);
      },
      child: widget.child,
    );
  }
}

/// Bottom sheet de confirmation pour le refresh du feed.
/// Oriente vers le bien-être digital. Affiche un message alternatif
/// si l'utilisateur refresh de manière compulsive (3+ en 10 min).
class _RefreshConfirmSheet extends StatelessWidget {
  final bool isCompulsive;
  final FacteurColors colors;

  const _RefreshConfirmSheet({
    required this.isCompulsive,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 24, bottom: 40, left: 20, right: 20),
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                isCompulsive
                    ? PhosphorIcons.heartbeat(PhosphorIconsStyle.bold)
                    : PhosphorIcons.arrowsClockwise(PhosphorIconsStyle.bold),
                color: colors.primary,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isCompulsive
                      ? 'Prends un moment'
                      : 'Rafraîchir l\'Explorer ?',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            isCompulsive
                ? 'Tu as déjà rafraîchi plusieurs fois. '
                    'As-tu vraiment besoin de plus d\'info maintenant ? '
                    'Essaie plutôt les derniers articles publiés.'
                : 'Les articles que tu n\'as pas lus seront déclassés '
                    'et remplacés par de nouveaux contenus.',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 15,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          if (isCompulsive) ...[
            // Primary: redirect to "Rester serein" mode (anti-addiction)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, 'serein'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Rester serein',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 10),
            // Secondary: refresh anyway
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context, 'refresh'),
                child: Text('Rafraîchir quand même',
                    style: TextStyle(color: colors.textSecondary)),
              ),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: colors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text('Annuler',
                        style: TextStyle(color: colors.textSecondary)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, 'refresh'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Rafraîchir',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
