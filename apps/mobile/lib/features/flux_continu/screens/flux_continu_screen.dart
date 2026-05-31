import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../../core/orchestration/first_impression_orchestrator.dart';
import '../../../core/providers/analytics_provider.dart';
import '../../../core/providers/navigation_providers.dart';
import '../../custom_topics/widgets/topic_chip.dart';
import '../../digest/models/digest_models.dart';
import '../../feed/models/content_model.dart';
import '../../feed/providers/swipe_hint_provider.dart';
import '../../feed/widgets/feedback_inline.dart';
import '../../lettres/widgets/lettres_notification_banner.dart';
import '../../notifications/widgets/notification_renudge_banner.dart';
import '../../well_informed/widgets/well_informed_prompt.dart';
import '../../../shared/widgets/loaders/loading_view.dart';
import '../models/flux_continu_models.dart';
import '../providers/flux_continu_provider.dart';
import '../widgets/citation_du_jour_card.dart';
import '../widgets/closing_card_v18.dart';
import '../widgets/flux_continu_article_card.dart';
import '../widgets/my_interests_intro.dart';
import '../widgets/my_interests_sheet.dart';
import '../widgets/section_block.dart';
import '../widgets/sticky_tab_bar.dart';
import '../widgets/tournee_folded_group_card.dart';
import '../../grille/widgets/grille_cta_card.dart';

/// Scroll offset at which the AppBar is swapped with the sticky tab bar.
const double _kStickyThreshold = 60.0;

/// Vertical offset the sticky bar consumes — used as a landing buffer
/// when scrolling a section into view so its banner doesn't disappear
/// behind the bar.
const double _kStickyBarHeight = 100.0;

/// Minimum delta (px) before the scroll-up FAB toggles, to avoid flicker
/// on tiny inertia bounces. Matches the legacy FeedScreen behaviour.
const double _kScrollDirThreshold = 12.0;

/// Below this scroll offset, the scroll-up FAB stays hidden even when the
/// user reverses direction (we're effectively already at the top).
const double _kFabHideAboveScroll = 380.0;

/// Min depth (px) the user must reach before we surface the
/// pull-to-refresh hint pill — avoids nudging after a tiny inertia scroll.
const double _kPullHintMinDepthPx = 800.0;

class FluxContinuScreen extends ConsumerStatefulWidget {
  const FluxContinuScreen({super.key});

  @override
  ConsumerState<FluxContinuScreen> createState() => _FluxContinuScreenState();
}

class _FluxContinuScreenState extends ConsumerState<FluxContinuScreen>
    with WidgetsBindingObserver {
  final ScrollController _scroll = ScrollController();
  final ScrollController _tabsScroll = ScrollController();
  final ValueNotifier<bool> _stickyVisible = ValueNotifier(false);
  final ValueNotifier<double> _scrollProgress = ValueNotifier(0);
  final ValueNotifier<int> _activeIndex = ValueNotifier(0);

  /// Controls whether the « Tournée du jour ✓ » group toggle is expanded.
  /// Resets to [false] (collapsed) on app pause.
  final ValueNotifier<bool> _tourneeGroupExpanded = ValueNotifier(false);

  final List<GlobalKey> _sectionKeys = [];

  /// Articles swipe-dismissed and replaced by a [FeedbackInline] banner at
  /// the same position. The hide API has already fired (via
  /// `markHiddenRemote`); resolution (chip / X / undo) drives
  /// `confirmDismiss` or `undoHide` on the provider.
  final Set<String> _pendingFeedback = <String>{};

  bool _showScrollTopFab = false;
  double _lastScrollPos = 0;

  // Pull-to-refresh discoverability pill. Shown briefly when the user
  // scrolls back to the top after having browsed deep enough (>=
  // [_kPullHintMinDepthPx]) so the gesture is signalled without being
  // mandatory. Throttled to once every ~2 minutes.
  bool _showPullHint = false;
  double _maxScrollDepthPx = 0;
  DateTime? _lastPullHintAt;
  Timer? _pullHintTimer;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _tabsScroll.dispose();
    _stickyVisible.dispose();
    _scrollProgress.dispose();
    _activeIndex.dispose();
    _tourneeGroupExpanded.dispose();
    _pullHintTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Collapse the « Tournée du jour ✓ » toggle when the app is backgrounded
    // so the user always sees it grouped on return — per spec.
    // `hidden` covers the moment the app becomes invisible on Android (Flutter
    // 3.13+); `paused` is the fallback and the reliable signal on iOS.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _tourneeGroupExpanded.value = false;
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final currentScroll = pos.pixels;
    final showSticky = currentScroll > _kStickyThreshold;
    if (_stickyVisible.value != showSticky) {
      _stickyVisible.value = showSticky;
    }
    final maxExtent = pos.maxScrollExtent;
    final nextProgress = maxExtent > 0
        ? (currentScroll / maxExtent).clamp(0.0, 1.0).toDouble()
        : 0.0;
    if (_scrollProgress.value != nextProgress) {
      _scrollProgress.value = nextProgress;
    }
    _updateActiveSection();
    _maybeFoldSections();

    if (currentScroll > _maxScrollDepthPx) {
      _maxScrollDepthPx = currentScroll;
    }

    // Scroll-up FAB: surfaces when the user reverses direction above the
    // hide threshold, hides on scroll-down or near the top. Same logic the
    // legacy feed used so the UX feels identical between the two screens.
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

    // Pull-to-refresh hint pill — discoverability cue when the user scrolls
    // back to the very top after browsing deep. Never triggers a refresh.
    final scrollingUp = pos.userScrollDirection == ScrollDirection.forward;
    if (scrollingUp &&
        currentScroll < 20 &&
        _maxScrollDepthPx >= _kPullHintMinDepthPx) {
      final now = DateTime.now();
      final last = _lastPullHintAt;
      if (last == null || now.difference(last) > const Duration(minutes: 2)) {
        _lastPullHintAt = now;
        setState(() => _showPullHint = true);
        _pullHintTimer?.cancel();
        _pullHintTimer = Timer(const Duration(milliseconds: 1800), () {
          if (mounted) setState(() => _showPullHint = false);
        });
      }
    }
  }

  /// Records sections that have fully scrolled above the viewport, **without
  /// collapsing them on screen**. The fold is deferred to the next cold launch.
  void _maybeFoldSections() {
    final value = ref.read(fluxContinuProvider).valueOrNull;
    if (value == null) return;
    final count = value.sections.length < _sectionKeys.length
        ? value.sections.length
        : _sectionKeys.length;
    final notifier = ref.read(fluxContinuProvider.notifier);
    for (var i = 0; i < count; i++) {
      final section = value.sections[i];
      if (value.isFolded(section)) continue;
      final key = _sectionKeys[i];
      final ctx = key.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final bottom = box.localToGlobal(Offset.zero).dy + box.size.height;
      if (bottom < -32) {
        notifier.markScrolledPastForNextSession(section);
      }
    }
  }

  void _updateActiveSection() {
    if (_sectionKeys.isEmpty) return;
    // Active = section that occupies the most visible area below the sticky
    // bar. The previous heuristic ("last section whose top has crossed
    // stickyBar + 200px lookahead") switched late on long sections because it
    // ignored how much of the upcoming section was already on screen. Viewport
    // dominance flips the active tab as soon as the next section becomes
    // majority-visible, which matches what the user is actually reading.
    const viewportTop = _kStickyBarHeight;
    final viewportBottom =
        viewportTop +
        (_scroll.hasClients ? _scroll.position.viewportDimension : 0.0);
    int activeAt = 0;
    double bestVisible = -1;
    for (var i = 0; i < _sectionKeys.length; i++) {
      final ctx = _sectionKeys[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject();
      if (box is! RenderBox) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      final bottom = top + box.size.height;
      final clampedTop = top.clamp(viewportTop, viewportBottom);
      final clampedBottom = bottom.clamp(viewportTop, viewportBottom);
      final visible = clampedBottom - clampedTop;
      if (visible > bestVisible) {
        bestVisible = visible;
        activeAt = i;
      }
    }
    if (_activeIndex.value != activeAt) {
      _activeIndex.value = activeAt;
      _alignTabsToActive(activeAt);
    }
  }

  void _alignTabsToActive(int index) {
    if (!_tabsScroll.hasClients) return;
    void doScroll() {
      if (!_tabsScroll.hasClients) return;
      final maxExtent = _tabsScroll.position.maxScrollExtent;
      const double estimatedTabWidth = 140.0;
      const double leftPadding = 12.0;
      final target = (index * estimatedTabWidth - leftPadding).clamp(
        0.0,
        maxExtent,
      );
      _tabsScroll.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }

    doScroll();
  }

  Future<void> _scrollToSection(int index) async {
    if (index < 0) return;
    if (index >= _sectionKeys.length) return;
    final targetKey = _sectionKeys[index];
    final ctx = targetKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject();
    if (box is! RenderBox) return;
    final scrollBox =
        _scroll.position.context.notificationContext?.findRenderObject()
            as RenderBox?;
    if (scrollBox == null) {
      await Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOutCubic,
      );
      return;
    }
    final delta =
        box.localToGlobal(Offset.zero, ancestor: scrollBox).dy -
        _kStickyBarHeight;
    final target = (_scroll.offset + delta).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    await _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeInOutCubic,
    );
  }

  /// Folds the Essentiel card then scrolls to [targetIndex]. The 50ms delay
  /// lets the fold settle so the scroll target's measured position is the
  /// post-fold one. Used by both "Tout l'essentiel" (scroll to Actus du
  /// jour) and "Tous mes articles ↓".
  Future<void> _foldEssentielAndScroll(
    EssentielSection essentiel,
    int targetIndex,
  ) async {
    ref.read(fluxContinuProvider.notifier).foldLocally(essentiel);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;
    await _scrollToSection(targetIndex);
  }

  Future<void> _exploreAllEssentiel(
    EssentielSection essentiel,
    int essentielIndex,
  ) async {
    final next = essentielIndex + 1;
    if (next >= _sectionKeys.length) return;
    await _foldEssentielAndScroll(essentiel, next);
  }

  /// "Tous mes articles ↓" action of the Essentiel hi-fi card: folds the
  /// card then opens Flâner.
  Future<void> _skipEssentielToExplorer(EssentielSection essentiel) async {
    final notifier = ref.read(fluxContinuProvider.notifier);
    notifier.foldLocally(essentiel);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;
    context.go(RoutePaths.flaner);
  }

  Future<void> _scrollToTop() async {
    if (!_scroll.hasClients) return;
    unawaited(HapticFeedback.lightImpact());
    _markSectionsAboveAsScrolledPast(null);
    await _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeInOutCubic,
    );
    if (!mounted) return;
    ref.read(fluxContinuProvider.notifier).applyPendingFoldsToState();
  }

  /// Pull-to-refresh handler. Wraps the provider's refresh + clears pending
  /// feedback (the new state replaces yesterday's session) + scrolls to top.
  Future<void> _handleRefresh() async {
    await ref.read(fluxContinuProvider.notifier).refresh();
    if (!mounted) return;
    if (_pendingFeedback.isNotEmpty) {
      setState(_pendingFeedback.clear);
    }
    if (_scroll.hasClients) {
      unawaited(
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  /// Opens the dedicated full-page view for a [FeedThemeSection]. The
  /// section's current snapshot is passed via `extra` so the page renders
  /// the cached items immediately rather than waiting on the provider.
  void _openThemeSection(BuildContext context, FeedThemeSection section) {
    final key = Uri.encodeComponent(sectionKey(section));
    context.push('${RoutePaths.fluxContinu}/theme/$key', extra: section);
  }

  /// Opens the dedicated full-page view for a [DigestTopicSection]
  /// (Actus du jour, Bonnes Nouvelles). Mirrors [_openThemeSection].
  void _openDigestSection(BuildContext context, DigestTopicSection section) {
    context.push(
      '${RoutePaths.fluxContinu}/section/${sectionKey(section)}',
      extra: section,
    );
  }

  /// Opens an article and, on return, promotes any sections the user
  /// scrolled past (or that sit above [fromSection]) to the live folded
  /// state. `fromSection == null` means the article was tapped from the
  /// Explorer feed (or via scroll-to-top sweep) — every editorial section
  /// is queued.
  ///
  /// The section the article was tapped from is excluded from the fold on
  /// return so the user finds the section still expanded at the same scroll
  /// position. For sections that *do* fold (those above [fromSection], or
  /// all of them when reading from Explorer), we measure their cumulative
  /// height before and after the resize and apply a silent
  /// [ScrollPosition.correctBy] so the article the user just left stays
  /// visually anchored.
  Future<void> _openArticle(
    BuildContext context,
    Object article, {
    FluxSection? fromSection,
  }) async {
    _markSectionsAboveAsScrolledPast(fromSection);
    final exceptKeys = fromSection == null
        ? const <String>{}
        : {sectionKey(fromSection)};
    final heightsBefore = _measureFoldCandidateHeights(exceptKeys);
    String? openedContentId;
    if (article is DigestItem) {
      openedContentId = article.contentId;
      await context.push(
        '${RoutePaths.fluxContinu}/content/${article.contentId}',
      );
    } else if (article is Content) {
      openedContentId = article.id;
      await context.push(
        '${RoutePaths.fluxContinu}/content/${article.id}',
        extra: article,
      );
    } else if (article is EssentielArticle) {
      openedContentId = article.contentId;
      await context.push(
        '${RoutePaths.fluxContinu}/content/${article.contentId}',
      );
    } else {
      return;
    }
    if (!mounted) return;
    // Mark the article as read in local state so the card immediately
    // shows the grey + check badge without waiting for a pull-to-refresh.
    ref.read(fluxContinuProvider.notifier).markArticleRead(openedContentId);
    ref
        .read(fluxContinuProvider.notifier)
        .applyPendingFoldsToState(exceptKeys: exceptKeys);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final heightsAfter = _measureFoldCandidateHeights(exceptKeys);
      final delta = heightsBefore - heightsAfter;
      if (delta <= 0.5) return;
      final position = _scroll.position;
      final corrected = (position.pixels - delta).clamp(
        0.0,
        position.maxScrollExtent,
      );
      position.correctBy(corrected - position.pixels);
    });
  }

  /// Cumulative on-screen height of the sections queued for fold (minus
  /// [exceptKeys]). Used as the delta to compensate scroll offset when the
  /// fold happens above the viewport.
  double _measureFoldCandidateHeights(Set<String> exceptKeys) {
    final value = ref.read(fluxContinuProvider).valueOrNull;
    if (value == null) return 0.0;
    final queued = ref
        .read(fluxContinuProvider.notifier)
        .persistQueuedSnapshot();
    if (queued.isEmpty) return 0.0;
    final count = math.min(value.sections.length, _sectionKeys.length);
    double sum = 0.0;
    for (var i = 0; i < count; i++) {
      final section = value.sections[i];
      final key = sectionKey(section);
      if (!queued.contains(key)) continue;
      if (exceptKeys.contains(key)) continue;
      final ctx = _sectionKeys[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      sum += box.size.height;
    }
    return sum;
  }

  void _markSectionsAboveAsScrolledPast(FluxSection? fromSection) {
    final value = ref.read(fluxContinuProvider).valueOrNull;
    if (value == null) return;
    final notifier = ref.read(fluxContinuProvider.notifier);
    final fromKey = fromSection == null ? null : sectionKey(fromSection);
    if (fromKey == null) {
      for (final s in value.sections) {
        unawaited(notifier.markScrolledPastForNextSession(s));
      }
      return;
    }
    for (final s in value.sections) {
      if (sectionKey(s) == fromKey) break;
      unawaited(notifier.markScrolledPastForNextSession(s));
    }
  }

  // ---------------------------------------------------------------------------
  // Inline-feedback flow (swipe-left)
  // ---------------------------------------------------------------------------

  void _onSwipeDismiss(String contentId) {
    if (contentId.isEmpty) return;
    final notifier = ref.read(fluxContinuProvider.notifier);
    unawaited(notifier.markHiddenRemote(contentId));
    setState(() => _pendingFeedback.add(contentId));
  }

  void _resolveFeedback(String contentId) {
    if (!mounted) return;
    if (!_pendingFeedback.contains(contentId)) return;
    setState(() => _pendingFeedback.remove(contentId));
    ref.read(fluxContinuProvider.notifier).confirmDismiss(contentId);
  }

  void _undoFeedback(String contentId) {
    if (!mounted) return;
    unawaited(ref.read(fluxContinuProvider.notifier).undoHide(contentId));
    setState(() => _pendingFeedback.remove(contentId));
  }

  void _trackFeedbackSubmit(String contentId, String feedbackType) {
    unawaited(
      ref
          .read(analyticsServiceProvider)
          .trackArticleFeedbackSubmitted(
            contentId: contentId,
            feedbackType: feedbackType,
            origin: 'flux_continu',
          ),
    );
  }

  Future<void> _onSelectFeedbackChip(
    BuildContext context,
    String contentId,
    FluxFeedbackChip chip,
  ) async {
    final state = ref.read(fluxContinuProvider).valueOrNull;
    final article = state == null ? null : _lookupArticle(state, contentId);
    switch (chip) {
      case FluxFeedbackChip.source:
        _trackFeedbackSubmit(contentId, 'less_source');
        if (article != null && context.mounted) {
          await TopicChip.showArticleSheet(
            context,
            articleToContent(article),
            initialSection: ArticleSheetSection.source,
            highlightInitialSection: true,
          );
        }
        _resolveFeedback(contentId);
      case FluxFeedbackChip.topic:
        _trackFeedbackSubmit(contentId, 'less_topic');
        if (article != null && context.mounted) {
          await TopicChip.showArticleSheet(
            context,
            articleToContent(article),
            initialSection: ArticleSheetSection.topic,
            highlightInitialSection: true,
          );
        }
        _resolveFeedback(contentId);
      case FluxFeedbackChip.alreadySeen:
        _trackFeedbackSubmit(contentId, 'already_seen');
        _resolveFeedback(contentId);
    }
  }

  /// Finds an article in the current state by its content id.
  Object? _lookupArticle(FluxContinuState state, String contentId) {
    for (final s in state.sections) {
      switch (s) {
        case EssentielSection(:final articles):
          for (final a in articles) {
            if (a.contentId == contentId) return a;
          }
        case DigestTopicSection(:final topics):
          for (final t in topics) {
            final lead = pickTopicLead(t);
            if (lead.contentId == contentId) return lead;
          }
        case FeedThemeSection(:final items):
          for (final c in items) {
            if (c.id == contentId) return c;
          }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(fluxContinuProvider);
    // Re-tap de l'onglet actif (depuis le shell) → remonter en haut.
    ref.listen(essentielScrollTriggerProvider, (_, __) => _scrollToTop());
    return Scaffold(
      backgroundColor: context.facteurColors.backgroundPrimary,
      // Header & footer vivent désormais dans le shell partagé (MainShell) :
      // l'écran ne fournit plus de bottomNavigationBar ni de header, et son top
      // inset est déjà consommé par le header fixe du shell.
      body: SafeArea(
        top: false,
        bottom: false,
        child: Stack(
          children: [
            state.when(
              loading: () => const LoadingView(),
              error: (e, _) => _ErrorView(
                error: e,
                onRetry: () => ref.read(fluxContinuProvider.notifier).refresh(),
              ),
              data: (data) => _buildContent(context, data),
            ),
            _StickyHostOverlay(
              stickyVisible: _stickyVisible,
              scrollProgress: _scrollProgress,
              activeIndex: _activeIndex,
              stateProvider: fluxContinuProvider,
              onTapTab: _scrollToSection,
              tabsController: _tabsScroll,
            ),
            // Floating "back to top" button — reveals on upward scroll above
            // the hide threshold, fades down on reverse / near top.
            Positioned(
              right: 16,
              bottom: 24,
              child: SafeArea(
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  offset: _showScrollTopFab
                      ? Offset.zero
                      : const Offset(0, 1.6),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    opacity: _showScrollTopFab ? 1.0 : 0.0,
                    child: _ScrollToTopButton(onTap: _scrollToTop),
                  ),
                ),
              ),
            ),
            // Pull-to-refresh discoverability pill.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 280),
                    opacity: _showPullHint ? 1.0 : 0.0,
                    child: _PullToRefreshHint(active: _showPullHint),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, FluxContinuState state) {
    final notifier = ref.read(fluxContinuProvider.notifier);
    final colors = context.facteurColors;
    final impressionSlot = ref.watch(firstImpressionSlotProvider);
    final totalArticles = state.sections.fold<int>(
      0,
      (sum, s) => sum + s.totalCount,
    );

    // When every editorial section is folded, the individual pile of
    // FoldedSectionCards is replaced by a single « Tournée du jour ✓ » toggle.
    final allFolded =
        state.sections.isNotEmpty &&
        state.sections.every((s) => state.isFolded(s));

    if (_sectionKeys.length != state.sections.length) {
      _sectionKeys
        ..clear()
        ..addAll(List.generate(state.sections.length, (_) => GlobalKey()));
    }

    return RefreshIndicator(
      onRefresh: _handleRefresh,
      color: colors.primary,
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // NB : le header (logo · streak · réglages) vit dans le shell partagé
          // (MainShell) — fixe, hors du scroll.
          SliverToBoxAdapter(
            child: impressionSlot == FirstImpressionSlot.renudgeBanner
                ? const NotificationRenudgeBanner()
                : const SizedBox.shrink(),
          ),
          SliverToBoxAdapter(
            child: impressionSlot == FirstImpressionSlot.wellInformed
                ? const WellInformedPrompt()
                : const SizedBox.shrink(),
          ),
          const SliverToBoxAdapter(child: LettresNotificationBanner()),
          // One SliverToBoxAdapter per section. Sections never resize during
          // a session (folds are deferred to the next cold launch), so the
          // simpler non-lazy adapter is sufficient and keeps the GlobalKey
          // measurement reliable.
          //
          // The "Mes intérêts" intro (V10) is injected once, right before the
          // first user-favorite theme section (`theme1` / `theme2`). The
          // computed index handles both ordering modes (normal / sereine) by
          // tracking the actual position of the first favorite kind.
          // When all sections are folded, collapse the pile into a single
          // « Tournée du jour ✓ » toggle. Tapping expands it back to the
          // individual FoldedSectionCards (each still re-openable).
          if (allFolded)
            SliverToBoxAdapter(
              child: ValueListenableBuilder<bool>(
                valueListenable: _tourneeGroupExpanded,
                builder: (_, expanded, __) {
                  if (!expanded) {
                    return TourneeFoldedGroupCard(
                      onTap: () => _tourneeGroupExpanded.value = true,
                    );
                  }
                  // Expanded: flatten the individual section slivers into a
                  // Column so they sit inside the single SliverToBoxAdapter.
                  final sectionWidgets = _buildSectionSlivers(
                    context: context,
                    state: state,
                    notifier: notifier,
                  ).map((s) => s.child!).toList();
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: sectionWidgets,
                  );
                },
              ),
            )
          else
            ..._buildSectionSlivers(
              context: context,
              state: state,
              notifier: notifier,
            ),
          if (state.sections.isEmpty)
            SliverToBoxAdapter(
              child: _EmptySectionsHint(onRetry: notifier.refresh),
            ),
          // Citation du jour — clôture éditoriale juste avant "Fin de
          // tournée". Liée au même flag closingDismissed pour rester
          // cohérente avec le "moment de fermeture". Quand la tournée est
          // entièrement repliée et que le `TourneeFoldedGroupCard` se
          // présente seul, on masque aussi la citation pour ne pas
          // apparaître au-dessus de ce toggle compact.
          if (state.quote != null && !state.closingDismissed)
            SliverToBoxAdapter(
              child: allFolded
                  ? ValueListenableBuilder<bool>(
                      valueListenable: _tourneeGroupExpanded,
                      builder: (_, expanded, __) => expanded
                          ? CitationDuJourCard(quote: state.quote!)
                          : const SizedBox.shrink(),
                    )
                  : CitationDuJourCard(quote: state.quote!),
            ),
          // La Grille du jour — récompense de fin de Tournée. Sliver additif
          // au-dessus de ClosingCardV18 (cette dernière n'est pas modifiée :
          // zéro régression, revert trivial). La carte se câble seule au
          // grilleProvider et ne rend rien tant que `GET today` n'a pas répondu.
          if (!state.closingDismissed)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 22, 16, 0),
                child: GrilleCtaCard(),
              ),
            ),
          SliverToBoxAdapter(
            child: state.closingDismissed
                ? const SizedBox.shrink()
                : ClosingCardV18(
                    articleCount: totalArticles,
                    onContinue: () async {
                      await notifier.markClosingDismissed();
                      if (context.mounted) context.go(RoutePaths.flaner);
                    },
                    onClose: () => notifier.markClosingDismissed(),
                  ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 92)),
        ],
      ),
    );
  }

  static bool _isFavoriteSection(FluxSection s) => s is FeedThemeSection;

  List<SliverToBoxAdapter> _buildSectionSlivers({
    required BuildContext context,
    required FluxContinuState state,
    required FluxContinuNotifier notifier,
  }) {
    final firstFavoriteIndex = state.sections.indexWhere(_isFavoriteSection);
    final favoriteCount = state.sections.where(_isFavoriteSection).length;
    final swipeLeftHintSeen =
        ref.watch(swipeLeftHintSeenProvider).valueOrNull ?? true;
    // When the user has consumed every editorial section, the inline
    // "Mes intérêts" intro reads as residual chrome — hide it so the
    // folded stack collapses tightly into the closing card.
    final allFolded =
        state.sections.isNotEmpty &&
        state.sections.every((s) => state.isFolded(s));

    final slivers = <SliverToBoxAdapter>[];
    for (var i = 0; i < state.sections.length; i++) {
      // Inject the "Mes intérêts" intro once, right before the first
      // user-favorite section. Skipped when favorites are first (no system
      // section above to separate from), absent altogether, or once every
      // section above has been folded (no editorial context left to break).
      if (i == firstFavoriteIndex && firstFavoriteIndex > 0 && !allFolded) {
        slivers.add(
          SliverToBoxAdapter(
            child: MyInterestsIntro(
              favoriteCount: favoriteCount,
              onTapManage: () => showMyInterestsBottomSheet(context),
            ),
          ),
        );
      }
      final section = state.sections[i];
      final isFavorite = _isFavoriteSection(section);
      slivers.add(
        SliverToBoxAdapter(
          child: KeyedSubtree(
            key: _sectionKeys[i],
            child: SectionBlock(
              section: section,
              isOpen: state.isOpen(section),
              isFolded: state.isFolded(section),
              onToggleMore: () => notifier.toggleMore(section),
              onUnfold: () => notifier.unfoldLocally(section),
              onFold: () => notifier.foldLocally(section),
              onTapArticle: (a, s) => _openArticle(context, a, fromSection: s),
              onDismissArticle: _onSwipeDismiss,
              pendingFeedbackIds: _pendingFeedback,
              onSelectFeedbackChip: (id, chip) =>
                  _onSelectFeedbackChip(context, id, chip),
              onResolveFeedback: _resolveFeedback,
              onUndoFeedback: _undoFeedback,
              enableSwipeHintOnFirstCard: i == 0 && !swipeLeftHintSeen,
              onSwipeHintComplete: () async {
                await markSwipeLeftHintSeen();
                if (mounted) ref.invalidate(swipeLeftHintSeenProvider);
              },
              onTapFavorite: isFavorite
                  ? () => showMyInterestsBottomSheet(context)
                  : null,
              onSeeAll: section is FeedThemeSection
                  ? () => _openThemeSection(context, section)
                  : section is DigestTopicSection
                  ? () => _openDigestSection(context, section)
                  : null,
              onTapExploreAll: section is EssentielSection
                  ? () => _exploreAllEssentiel(section, i)
                  : null,
              onTapSeeAllDown: section is EssentielSection
                  ? () => _skipEssentielToExplorer(section)
                  : null,
              isMarkedForNextSession: state.isMarkedForNextSession(section),
              nextSectionAccent: i + 1 < state.sections.length
                  ? state.sections[i + 1].accent
                  : null,
              nextSectionLabel: i + 1 < state.sections.length
                  ? state.sections[i + 1].label
                  : null,
              onNextSection:
                  (section is EssentielSection ||
                      i >= state.sections.length - 1)
                  ? null
                  : () => _advanceToNextSection(section, i),
            ),
          ),
        ),
      );
    }
    return slivers;
  }

  /// "Sujet suivant" tap handler for in-Tournée progression. Marks the
  /// current section as consumed for the next session (without folding it
  /// visually) and smooth-scrolls to the next section banner. If the target
  /// section is currently folded, unfolds it first so the user lands on an
  /// expanded banner rather than a collapsed card.
  Future<void> _advanceToNextSection(FluxSection section, int index) async {
    unawaited(HapticFeedback.lightImpact());
    unawaited(
      ref
          .read(fluxContinuProvider.notifier)
          .markScrolledPastForNextSession(section),
    );
    final state = ref.read(fluxContinuProvider).valueOrNull;
    final nextIdx = index + 1;
    if (state != null && nextIdx < state.sections.length) {
      final next = state.sections[nextIdx];
      if (state.isFolded(next)) {
        ref.read(fluxContinuProvider.notifier).unfoldLocally(next);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (!mounted) return;
      }
    }
    // Let the "Terminé" pop play before the scroll kicks in, so the user
    // sees the green confirmation flash on its own frame.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    await _scrollToSection(nextIdx);
  }
}

class _StickyHostOverlay extends ConsumerWidget {
  final ValueNotifier<bool> stickyVisible;
  final ValueNotifier<double> scrollProgress;
  final ValueNotifier<int> activeIndex;
  final AsyncNotifierProvider<FluxContinuNotifier, FluxContinuState>
  stateProvider;
  final ValueChanged<int> onTapTab;
  final ScrollController tabsController;

  const _StickyHostOverlay({
    required this.stickyVisible,
    required this.scrollProgress,
    required this.activeIndex,
    required this.stateProvider,
    required this.onTapTab,
    required this.tabsController,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections =
        ref.watch(stateProvider).valueOrNull?.sections ?? const <FluxSection>[];
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: ValueListenableBuilder<bool>(
        valueListenable: stickyVisible,
        builder: (context, visible, _) {
          final showSticky = visible && sections.isNotEmpty;
          if (!showSticky) {
            return const SizedBox.shrink();
          }
          final tabs = <StickyTab>[
            for (final s in sections)
              StickyTab(label: s.label, accent: s.accent),
          ];
          return ValueListenableBuilder<int>(
            valueListenable: activeIndex,
            builder: (context, idx, _) => ValueListenableBuilder<double>(
              valueListenable: scrollProgress,
              builder: (context, progress, _) => StickyTabBar(
                tabs: tabs,
                activeIndex: idx.clamp(0, tabs.length - 1),
                progress: progress,
                onTapTab: onTapTab,
                tabsController: tabsController,
                title: 'Tournée du jour',
                showFilterBar: false,
              ),
            ),
          );
        },
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
    // Same liquidglass mix as StickyBackdrop so the pill reads as part of the
    // same surface family (parchment in light, dark-surface tint in dark).
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
            borderRadius: _kRadius,
            onTap: onTap,
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: fillColor,
                borderRadius: _kRadius,
                border: Border.all(color: borderColor, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 12,
                    spreadRadius: -4,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    PhosphorIcons.caretUp(PhosphorIconsStyle.bold),
                    size: 16,
                    color: colors.textPrimary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Remonter',
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PullToRefreshHint extends StatefulWidget {
  final bool active;
  const _PullToRefreshHint({required this.active});

  @override
  State<_PullToRefreshHint> createState() => _PullToRefreshHintState();
}

class _PullToRefreshHintState extends State<_PullToRefreshHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounceController;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.active) _bounceController.repeat();
  }

  @override
  void didUpdateWidget(_PullToRefreshHint oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_bounceController.isAnimating) {
      _bounceController.repeat();
    } else if (!widget.active && _bounceController.isAnimating) {
      _bounceController.stop();
      _bounceController.value = 0;
    }
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(FacteurRadius.full),
            boxShadow: [
              BoxShadow(
                color: colors.primary.withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _bounceController,
                builder: (context, child) {
                  final t = _bounceController.value;
                  final offset = math.sin(t * math.pi * 2) * 3.0;
                  return Transform.translate(
                    offset: Offset(0, offset),
                    child: child,
                  );
                },
                child: Icon(
                  PhosphorIcons.arrowDown(PhosphorIconsStyle.bold),
                  size: 14,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Tirer pour rafraîchir',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final Object error;
  final Future<void> Function() onRetry;

  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FacteurSpacing.space8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 48, color: colors.textTertiary),
            const SizedBox(height: FacteurSpacing.space3),
            Text(
              'Le flux continu est indisponible.',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: FacteurSpacing.space4),
            OutlinedButton(onPressed: onRetry, child: const Text('Réessayer')),
          ],
        ),
      ),
    );
  }
}

class _EmptySectionsHint extends StatelessWidget {
  final Future<void> Function() onRetry;
  const _EmptySectionsHint({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.all(FacteurSpacing.space6),
      child: Column(
        children: [
          Icon(Icons.inbox_outlined, size: 36, color: colors.textTertiary),
          const SizedBox(height: 8),
          Text(
            'Pas encore de contenu pour la tournée du jour.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: const Text('Recharger')),
        ],
      ),
    );
  }
}
