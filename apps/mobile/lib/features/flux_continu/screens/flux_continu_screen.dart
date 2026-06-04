import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart'
    show ValueListenable, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../../core/nudges/nudge_counters.dart';
import '../../../core/orchestration/first_impression_orchestrator.dart';
import '../../../core/providers/analytics_provider.dart';
import '../../../core/providers/navigation_providers.dart';
import '../../custom_topics/widgets/topic_chip.dart';
import '../../digest/models/digest_models.dart';
import '../../feed/models/content_model.dart';
import '../../feed/providers/swipe_hint_provider.dart';
import '../../feed/widgets/feedback_inline.dart';
import '../../lettres/widgets/lettres_notification_banner.dart';
import '../../notifications/widgets/notification_activation_modal.dart';
import '../../notifications/widgets/notification_renudge_banner.dart';
import '../../onboarding/widgets/theme_choice_bottom_sheet.dart';
import '../../well_informed/widgets/well_informed_prompt.dart';
import '../../../shared/strings/loader_error_strings.dart';
import '../../../shared/widgets/loaders/loading_view.dart';
import '../models/flux_continu_models.dart';
import '../providers/flux_continu_provider.dart';
import '../utils/section_snap.dart';
import '../widgets/citation_du_jour_card.dart';
import '../widgets/closing_card_v18.dart';
import '../widgets/flux_continu_article_card.dart';
import '../widgets/my_interests_intro.dart';
import '../widgets/tournee_composer_sheet.dart';
import '../widgets/geoloc_prompt_banner.dart';
import '../widgets/section_block.dart';
import '../widgets/sticky_tab_bar.dart';
import '../../grille/providers/grille_provider.dart';
import '../../grille/widgets/grille_cta_card.dart';

/// Scroll offset at which the AppBar is swapped with the sticky tab bar.
const double _kStickyThreshold = 60.0;

/// Vertical offset the sticky bar consumes — used as a landing buffer
/// when scrolling a section into view so its banner doesn't disappear
/// behind the bar. Trimmed from 90 → 54 after the head title (~36px) was
/// dropped from the sticky overlay: tabs row (48) + progress track (4) + a
/// couple px of slack.
const double _kStickyBarHeight = 54.0;

/// Hauteur (px) du **footer glassmorphique partagé** (barre d'onglets) qui
/// recouvre le bas de la zone scrollable — le contenu passe dessous. On la
/// retranche du cadrage « bas de section » pour que les dernières cartes (le
/// « Lire plus ») ne soient pas tronquées par le footer. La safe-area du bas
/// (encoche / home indicator) s'y **ajoute dynamiquement** (cf.
/// [_recomputeSnapAnchors]). Tune-able à l'œil : monter si le bas reste rogné.
const double _kFooterBarHeight = 50.0;

// Section-snap tuning lives in `utils/section_snap.dart` (kSnapCaptureFraction,
// kBoundaryCrossVelocity, kSnapEpsilon, kSnapSpring) so the resting-position
// arithmetic stays a pure, unit-testable function. The snap itself is woven
// into the fling's ballistic phase by [_SectionSnapPhysics] below.

/// Minimum delta (px) before the scroll-up FAB toggles, to avoid flicker
/// on tiny inertia bounces. Matches the legacy FeedScreen behaviour.
const double _kScrollDirThreshold = 12.0;

/// Below this scroll offset, the scroll-up FAB stays hidden even when the
/// user reverses direction (we're effectively already at the top).
const double _kFabHideAboveScroll = 380.0;

/// Min depth (px) the user must reach before we surface the
/// pull-to-refresh hint pill — avoids nudging after a tiny inertia scroll.
const double _kPullHintMinDepthPx = 800.0;

/// Onglets sticky des deux cartes virtuelles.
/// Accent intentionnellement neutre/crème (vs les accents vifs des sections
/// éditoriales) pour signaler visuellement que Grille et Citation sont du
/// contenu "pause / loisir" — le surligneur marker sera quasi discret.
const _kLeisureTabAccent = Color(0xFFB8A898);
const _motDuJourTab = StickyTab(
  label: 'Mot du jour',
  accent: _kLeisureTabAccent,
);
const _citationTab = StickyTab(
  label: 'Citation du jour',
  accent: _kLeisureTabAccent,
);
const _closingTab = StickyTab(
  label: 'Fin de tournée',
  accent: Color(0xFF2E7D32),
);

class FluxContinuScreen extends ConsumerStatefulWidget {
  const FluxContinuScreen({super.key});

  @override
  ConsumerState<FluxContinuScreen> createState() => _FluxContinuScreenState();
}

class _FluxContinuScreenState extends ConsumerState<FluxContinuScreen> {
  final ScrollController _scroll = ScrollController();
  final ScrollController _tabsScroll = ScrollController();
  final ValueNotifier<bool> _stickyVisible = ValueNotifier(false);
  final ValueNotifier<double> _scrollProgress = ValueNotifier(0);
  final ValueNotifier<int> _activeIndex = ValueNotifier(0);
  final ValueNotifier<_SectionPassagePulse?> _sectionPassagePulse =
      ValueNotifier(null);

  final List<GlobalKey> _sectionKeys = [];

  // Clés dédiées aux cartes virtuelles qui ont désormais un onglet sticky.
  // La Grille n'est montée qu'à un seul endroit à la fois (après Actus, ou en
  // fallback bas) → une seule clé suffit. Disjointes de [_sectionKeys] : le
  // suivi de section active (qui itère _sectionKeys) reste inchangé.
  final GlobalKey _grilleKey = GlobalKey();
  final GlobalKey _citationKey = GlobalKey();
  final GlobalKey _closingKey = GlobalKey();

  // Clés des « entrées sticky » dans l'ordre exact des slivers : sections +
  // Mot du jour + Citation + Fin de tournée. Source unique pour le suivi de
  // section active et le scroll-to-section (les onglets en dérivent via
  // [_syncStickyEntries]).
  final List<GlobalKey> _stickyEntryKeys = [];

  /// Sliver « Grille du jour » (carte d'entrée de La Grille). Padding maquette
  /// partagé par ses deux sites de rendu : juste après « Actus du jour » (cas
  /// nominal) et le fallback bas quand le digest est absent. Wrappé dans un
  /// `KeyedSubtree(_grilleKey)` pour exposer la carte au suivi sticky.
  SliverToBoxAdapter get _grilleSliver => SliverToBoxAdapter(
        child: KeyedSubtree(
          key: _grilleKey,
          child: const Padding(
            padding: EdgeInsets.fromLTRB(16, 22, 16, 0),
            child: GrilleCtaCard(),
          ),
        ),
      );

  /// Articles swipe-dismissed and replaced by a [FeedbackInline] banner at
  /// the same position. The hide API has already fired (via
  /// `markHiddenRemote`); resolution (chip / X / undo) drives
  /// `confirmDismiss` or `undoHide` on the provider.
  final Set<String> _pendingFeedback = <String>{};

  bool _showScrollTopFab = false;
  double _lastScrollPos = 0;
  int _passagePulseSequence = 0;

  /// Mutable, stable holder of the section-start anchors (absolute scroll
  /// pixels). Passed *by reference* to the immutable [_SectionSnapPhysics],
  /// which reads it live — the physics is rebuilt every frame and must never
  /// own a copy. Recomputed only on layout/content changes (sections don't
  /// resize mid-session), never per scroll frame.
  final _SnapAnchors _snapAnchors = _SnapAnchors();
  bool _snapAnchorsRecomputeScheduled = false;

  /// Safe-area inset at the bottom (home indicator / notch), captured in
  /// [build]. Added to [_kFooterBarHeight] so the « bottom of section » frame
  /// clears the shared footer on every device. Read in [_recomputeSnapAnchors]
  /// (a post-frame callback) where reading `MediaQuery` directly is unsafe.
  double _safeAreaBottom = 0;


  /// Garde-fou : le flow post-onboarding (dialog customs échoués + modales
  /// thème & notifications) ne doit se jouer qu'une seule fois par montage,
  /// jamais sur un refetch/scroll/rebuild.
  bool _postOnboardingFlowRan = false;

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
    // Compte une ouverture du feed par montage de l'écran. Alimente la bannière
    // de demande de géoloc (déclenchée après 5 ouvertures, cf.
    // geoloc_prompt_provider). Best-effort, n'impacte pas le rendu.
    unawaited(NudgeCounters.increment(NudgeCounters.feedOpenCount));
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _tabsScroll.dispose();
    _stickyVisible.dispose();
    _scrollProgress.dispose();
    _activeIndex.dispose();
    _sectionPassagePulse.dispose();
    _pullHintTimer?.cancel();
    super.dispose();
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

  void _updateActiveSection() {
    if (_stickyEntryKeys.isEmpty) return;
    // Active = sticky entry that occupies the most visible area below the
    // sticky bar. The previous heuristic ("last section whose top has crossed
    // stickyBar + 200px lookahead") switched late on long sections because it
    // ignored how much of the upcoming section was already on screen. Viewport
    // dominance flips the active tab as soon as the next entry becomes
    // majority-visible, which matches what the user is actually reading. Itère
    // la liste combinée (sections + Mot du jour + Citation).
    const viewportTop = _kStickyBarHeight;
    final viewportBottom = viewportTop +
        (_scroll.hasClients ? _scroll.position.viewportDimension : 0.0);
    int activeAt = 0;
    double bestVisible = -1;
    for (var i = 0; i < _stickyEntryKeys.length; i++) {
      final ctx = _stickyEntryKeys[i].currentContext;
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
      // Strong section haptic when the active tab flips section under the
      // sticky bar. Gated on visibility so we don't buzz during the initial
      // layout / top-of-page scroll, before the sticky is even revealed. The
      // snap's one-step cap (cf. resolveSnapTarget) keeps a fling to a single
      // boundary crossing, so this fires exactly once per step.
      if (_stickyVisible.value) {
        unawaited(_triggerSectionChangeHaptic());
        _pulsePassageForStickyIndex(activeAt);
      }
      _activeIndex.value = activeAt;
      _alignTabsToActive(activeAt);
    }
  }

  int _sectionIndexForStickyIndex(int stickyIndex) {
    if (stickyIndex < 0 || stickyIndex >= _stickyEntryKeys.length) return -1;
    final key = _stickyEntryKeys[stickyIndex];
    for (var i = 0; i < _sectionKeys.length; i++) {
      if (identical(_sectionKeys[i], key)) return i;
    }
    return -1;
  }

  void _pulsePassageForStickyIndex(int stickyIndex) {
    final sectionIndex = _sectionIndexForStickyIndex(stickyIndex);
    if (sectionIndex <= 0) return;
    _sectionPassagePulse.value = _SectionPassagePulse(
      index: sectionIndex - 1,
      sequence: ++_passagePulseSequence,
    );
  }

  bool _onScrollNotification(ScrollNotification n) {
    return false;
  }

  Future<void> _triggerSectionChangeHaptic() async {
    try {
      await Haptics.vibrate(HapticsType.heavy, usage: HapticsUsage.touch);
    } catch (_) {
      await HapticFeedback.heavyImpact();
    }
  }

  /// Recomputes the section framing offsets from current layout. Each sticky
  /// entry yields a [SectionFrame]:
  /// - `top`    : the offset that brings the entry's top flush under the sticky
  ///   bar (identical maths to [_scrollToSection]);
  /// - `bottom` : the offset that brings the entry's bottom flush to the footer.
  ///   It is `> top` only for entries taller than the usable viewport — those
  ///   get a free-reading interior; shorter entries collapse `bottom == top`.
  ///
  /// [resolveSnapTarget] turns these into the edge-triggered feel: free while a
  /// section fills the screen, snap to the next frame in the travel direction
  /// otherwise. Offset-invariant (we add `_scroll.offset` back), so it is safe
  /// to run mid-scroll.
  void _recomputeSnapAnchors() {
    if (!_scroll.hasClients) {
      _snapAnchors.values = const [];
      return;
    }
    final scrollBox = _scroll.position.context.notificationContext
        ?.findRenderObject() as RenderBox?;
    if (scrollBox == null) return;
    final offset = _scroll.offset;
    // Visible bottom edge: the scroll area extends under the shared footer
    // (content passes beneath it), so the section bottom must land above the
    // footer bar + bottom safe-area, else the last cards (« Lire plus ») are
    // truncated.
    final visibleBottom =
        scrollBox.size.height - (_kFooterBarHeight + _safeAreaBottom);
    final result = <SectionFrame>[];
    for (final key in _stickyEntryKeys) {
      final ctx = key.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final topGlobal = box.localToGlobal(Offset.zero, ancestor: scrollBox).dy;
      final top = offset + (topGlobal - _kStickyBarHeight);
      // Bottom flush to the visible bottom (above the footer). `bottom - top =
      // sectionHeight - usableViewport`, so `bottom > top` exactly when the
      // section is taller than the visible area — i.e. only those gain a
      // free-reading zone.
      final bottom = offset + (topGlobal + box.size.height) - visibleBottom;
      result.add((top: top, bottom: bottom));
    }
    result.sort((a, b) => a.top.compareTo(b.top));
    _snapAnchors.values = result;
  }

  /// Defers an anchor recompute to the next post-frame (when layout is settled),
  /// coalescing the bursts of builds that "Plus de…"/content changes produce
  /// into a single pass. Never runs per scroll frame.
  void _scheduleAnchorRecompute() {
    if (_snapAnchorsRecomputeScheduled) return;
    _snapAnchorsRecomputeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _snapAnchorsRecomputeScheduled = false;
      if (!mounted) return;
      _recomputeSnapAnchors();
    });
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
    if (index >= _stickyEntryKeys.length) return;
    final targetKey = _stickyEntryKeys[index];
    final ctx = targetKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject();
    if (box is! RenderBox) return;
    final scrollBox = _scroll.position.context.notificationContext
        ?.findRenderObject() as RenderBox?;
    if (scrollBox == null) {
      await Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOutCubic,
      );
      return;
    }
    final delta = box.localToGlobal(Offset.zero, ancestor: scrollBox).dy -
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

  Future<void> _scrollToTop() async {
    if (!_scroll.hasClients) return;
    unawaited(HapticFeedback.lightImpact());
    await _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeInOutCubic,
    );
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

  /// PR « Sources dans la Tournée » — ouvre la vue détail d'une section source
  /// (curation complète de la source). Miroir de [_openThemeSection], route
  /// `/flux-continu/source/:id` (id = sectionKey = `source:<uuid>`).
  void _openSourceSection(BuildContext context, FeedThemeSection section) {
    final key = Uri.encodeComponent(sectionKey(section));
    context.push('${RoutePaths.fluxContinu}/source/$key', extra: section);
  }

  /// Opens the dedicated full-page view for a [DigestTopicSection]
  /// (Actus du jour, Bonnes Nouvelles). Mirrors [_openThemeSection].
  void _openDigestSection(BuildContext context, DigestTopicSection section) {
    context.push(
      '${RoutePaths.fluxContinu}/section/${sectionKey(section)}',
      extra: section,
    );
  }

  /// Opens an article and, on return, marks it read in local state so the
  /// card immediately shows the grey + check badge without waiting for a
  /// pull-to-refresh.
  Future<void> _openArticle(BuildContext context, Object article) async {
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
    ref.read(fluxContinuProvider.notifier).markArticleRead(openedContentId);
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
      ref.read(analyticsServiceProvider).trackArticleFeedbackSubmitted(
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

  // ---------------------------------------------------------------------------
  // Flow post-onboarding (présenté sur Essentiel chargé, cf.
  // postOnboardingFlowPendingProvider)
  // ---------------------------------------------------------------------------

  /// Planifie le flow post-onboarding pour le prochain post-frame, une seule
  /// fois par montage. Le garde-fou est armé immédiatement pour qu'aucun
  /// rebuild concurrent n'empile de second callback.
  void _schedulePostOnboardingFlow() {
    if (_postOnboardingFlowRan) return;
    _postOnboardingFlowRan = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runPostOnboardingFlow());
    });
  }

  /// Joue, dans l'ordre, sur le `context`/`ref` stables d'Essentiel chargé :
  /// 1. le dialog des sujets personnalisés échoués (si non vide),
  /// 2. la modal de choix de thème,
  /// 3. la modal d'activation des notifications.
  /// La page Essentiel chargée sert de fond aux modales : à leur fermeture elle
  /// est révélée intacte (plus d'écran gris ni de contexte démonté).
  Future<void> _runPostOnboardingFlow() async {
    if (!mounted) return;
    final failedCustomTopics = ref.read(postOnboardingFlowPendingProvider);
    if (failedCustomTopics == null) return;
    // Consomme le flag immédiatement : un refetch/rebuild ne doit pas rejouer.
    ref.read(postOnboardingFlowPendingProvider.notifier).state = null;

    if (mounted && failedCustomTopics.isNotEmpty) {
      // Dialog bloquant : les bottom sheets suivants poseraient un barrier qui
      // masquerait une SnackBar. Le dialog garantit que l'utilisateur voit
      // l'info ("tu pourras les réajouter").
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(
            OnboardingFallbackStrings.failedCustomTopicsMessage(
              failedCustomTopics,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }

    if (mounted) {
      await showThemeChoiceBottomSheet(context, ref);
    }

    if (mounted) {
      await showNotificationActivationModal(
        context,
        ref,
        trigger: ActivationTrigger.onboarding,
      );
      // Marque la modal notif comme consommée pour la session : l'arbitre
      // first-impression ne la reproposera pas et laisse passer les nudges.
      if (mounted) {
        ref.read(notifModalConsumedThisSessionProvider.notifier).state = true;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(fluxContinuProvider);
    // Re-tap de l'onglet actif (depuis le shell) → remonter en haut.
    ref.listen(essentielScrollTriggerProvider, (_, __) => _scrollToTop());
    // Flow post-onboarding : joué une seule fois quand Essentiel a chargé ses
    // données (derrière les modales thème & notifications). Couvre la
    // transition loading→data (via le listen) et le cas où l'état est déjà
    // `data` au montage (check direct planifié en post-frame).
    ref.listen<AsyncValue<FluxContinuState>>(fluxContinuProvider, (_, next) {
      if (next is AsyncData<FluxContinuState> &&
          ref.read(postOnboardingFlowPendingProvider) != null) {
        _schedulePostOnboardingFlow();
      }
    });
    if (state is AsyncData<FluxContinuState> &&
        ref.read(postOnboardingFlowPendingProvider) != null) {
      _schedulePostOnboardingFlow();
    }
    // Mot du jour présent ⇔ la Grille a un mot du jour (sinon GrilleCtaCard se
    // masque). `.select` ne reconstruit que lorsque la présence bascule.
    final grillePresent = ref.watch(
      grilleProvider.select((v) => v.valueOrNull?.today != null),
    );
    // Source unique : aligne [_sectionKeys] + [_stickyEntryKeys] sur les slivers
    // et dérive les descripteurs d'onglets (label+accent), dans le même ordre.
    final stickyTabs = _syncStickyEntries(state.valueOrNull, grillePresent);
    // Sections don't resize mid-session, so we refresh the snap anchors only on
    // these content/layout-driven rebuilds — never per scroll frame.
    _safeAreaBottom = MediaQuery.viewPaddingOf(context).bottom;
    _scheduleAnchorRecompute();
    return Scaffold(
      backgroundColor: context.facteurColors.backgroundPrimary,
      // Header & footer vivent dans le scaffold de page partagé :
      // l'écran ne fournit plus de bottomNavigationBar ni de header, et son top
      // inset est déjà consommé par le header partagé.
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
              tabs: stickyTabs,
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

  /// Construit la liste ordonnée d'« entrées sticky » (sections + cartes
  /// virtuelles Mot du jour / Citation) reflétant l'ordre exact des slivers de
  /// [_buildContent]. Synchronise [_sectionKeys] (1 clé/section) et
  /// [_stickyEntryKeys] (clés combinées pour le suivi actif + le scroll), puis
  /// retourne les descripteurs d'onglets (label+accent) dans le même ordre.
  List<StickyTab> _syncStickyEntries(
    FluxContinuState? state,
    bool grillePresent,
  ) {
    if (state == null) {
      _stickyEntryKeys.clear();
      return const [];
    }
    if (_sectionKeys.length != state.sections.length) {
      _sectionKeys
        ..clear()
        ..addAll(List.generate(state.sections.length, (_) => GlobalKey()));
    }
    // « Actus du jour » = DigestTopicSection kind essentiel : la Grille est
    // rendue juste après elle (sinon en fallback bas, après la Citation).
    final hasActus = state.sections.any(
      (s) => s is DigestTopicSection && s.kind == SectionKind.essentiel,
    );
    final citationPresent = state.quote != null && !state.closingDismissed;

    final keys = <GlobalKey>[];
    final tabs = <StickyTab>[];
    void add(GlobalKey key, StickyTab tab) {
      keys.add(key);
      tabs.add(tab);
    }

    for (var i = 0; i < state.sections.length; i++) {
      final section = state.sections[i];
      add(
        _sectionKeys[i],
        StickyTab(label: section.label, accent: section.accent),
      );
      if (grillePresent &&
          section is DigestTopicSection &&
          section.kind == SectionKind.essentiel) {
        add(_grilleKey, _motDuJourTab);
      }
    }
    if (citationPresent) {
      add(_citationKey, _citationTab);
    }
    // Fallback bas : Grille rendue après la Citation quand il n'y a pas d'Actus
    // (cf. `if (!hasActus) _grilleSliver` dans _buildContent).
    if (!hasActus && grillePresent) {
      add(_grilleKey, _motDuJourTab);
    }
    add(_closingKey, _closingTab);

    _stickyEntryKeys
      ..clear()
      ..addAll(keys);
    return tabs;
  }

  Widget _buildContent(BuildContext context, FluxContinuState state) {
    final notifier = ref.read(fluxContinuProvider.notifier);
    final colors = context.facteurColors;
    final impressionSlot = ref.watch(firstImpressionSlotProvider);
    final totalArticles = state.sections.fold<int>(
      0,
      (sum, s) => sum + s.totalCount,
    );
    // Android peut fermer l'app programmatiquement ; iOS l'interdit (App
    // Store) → on y montre une phrase de clôture au lieu du bouton.
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;

    // « Actus du jour » = DigestTopicSection kind essentiel (identité robuste,
    // cf. _buildSectionSlivers). Quand elle existe, la Grille est rendue juste
    // après elle ; sinon on garde la Grille en fallback bas (digest absent).
    final hasActus = state.sections.any(
      (s) => s is DigestTopicSection && s.kind == SectionKind.essentiel,
    );
    // NB : [_sectionKeys] est synchronisé en amont par [_syncStickyEntries]
    // (appelé dans build) → on s'appuie sur cet alignement ici.

    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: RefreshIndicator(
        onRefresh: _handleRefresh,
        color: colors.primary,
        child: CustomScrollView(
          controller: _scroll,
          // Section-anchored snap woven into the fling's ballistic phase. The
          // platform parent (Bouncing/Clamping) is preserved via `applyTo`, so
          // overscroll/pull-to-refresh feel native; the snap only chooses the
          // resting position. AlwaysScrollable keeps the page scrollable even
          // when content is short.
          physics: AlwaysScrollableScrollPhysics(
            parent: _SectionSnapPhysics(
              anchors: _snapAnchors,
            ),
          ),
          slivers: [
            // NB : le header (logo · streak · réglages) vit dans le scaffold de
            // page partagé — fixe, hors du scroll.
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
            SliverToBoxAdapter(
              child: impressionSlot == FirstImpressionSlot.geolocPrompt
                  ? const GeolocPromptBanner()
                  : const SizedBox.shrink(),
            ),
            const SliverToBoxAdapter(child: LettresNotificationBanner()),
            // One SliverToBoxAdapter per section. Sections never resize during
            // a session, so the simpler non-lazy adapter is sufficient and
            // keeps the GlobalKey measurement reliable.
            //
            // The "Mes intérêts" intro (V10) is injected once, right before the
            // first user-favorite theme section. The computed index handles
            // both ordering modes (normal / sereine) by tracking the actual
            // position of the first favorite kind.
            ..._buildSectionSlivers(
              context: context,
              state: state,
              notifier: notifier,
            ),
            if (state.sections.isEmpty)
              SliverToBoxAdapter(
                child: _EmptySectionsHint(onRetry: notifier.refresh),
              ),
            // Citation du jour — clôture éditoriale en fin de tournée. Affichée
            // dès qu'une citation existe et que la tournée n'est pas clôturée
            // (`closingDismissed`) : replier la tournée ne doit pas la masquer,
            // c'est un rituel de fin de tournée.
            if (state.quote != null && !state.closingDismissed)
              SliverToBoxAdapter(
                child: KeyedSubtree(
                  key: _citationKey,
                  child: CitationDuJourCard(quote: state.quote!),
                ),
              ),
            // « Le mot du jour » — récompense de fin de Tournée. Sliver additif
            // au-dessus de ClosingCardV18 (cette dernière n'est pas modifiée :
            // zéro régression, revert trivial). La carte se câble seule au
            // grilleProvider et ne rend rien tant que `GET today` n'a pas répondu.
            // Hors gate `closingDismissed` : elle reste dans le feed même après
            // fermeture de la tournée (en état « déjà jouée »), et se masque
            // seule (SizedBox.shrink) s'il n'y a pas de mot du jour.
            // Grille — rendue juste après « Actus du jour » (cf.
            // _buildSectionSlivers) quand cette section existe. Fallback bas
            // ici uniquement si le digest est absent / la liste vide, pour ne
            // jamais perdre la Grille. Hors gate `closingDismissed`.
            if (!hasActus) _grilleSliver,
            // Carte « Fin de tournée » — toujours affichée (jamais masquée) : elle
            // reste le repère de clôture même après être passé sur Flâner.
            // « Continuer » navigue vers Flâner sans masquer la carte. « Refermer »
            // ferme réellement l'app sur Android (SystemNavigator.pop) ; sur iOS,
            // la fermeture programmatique est interdite → on masque le bouton et
            // on affiche une phrase de clôture à la place.
            SliverToBoxAdapter(
              child: KeyedSubtree(
                key: _closingKey,
                child: ClosingCardV18(
                  articleCount: totalArticles,
                  onContinue: () => context.go(RoutePaths.flaner),
                  onClose: isAndroid ? () => SystemNavigator.pop() : null,
                  closeHint: isAndroid
                      ? null
                      : 'Vous pouvez refermer l’app — à demain',
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 92)),
          ],
        ),
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

    final slivers = <SliverToBoxAdapter>[];
    for (var i = 0; i < state.sections.length; i++) {
      // Inject the "Mes intérêts" intro once, right before the first
      // user-favorite section. Skipped when favorites are first (no system
      // section above to separate from) or absent altogether.
      if (i == firstFavoriteIndex && firstFavoriteIndex > 0) {
        slivers.add(
          SliverToBoxAdapter(
            child: MyInterestsIntro(
              favoriteCount: favoriteCount,
              onTapManage: () => showTourneeComposerSheet(context),
            ),
          ),
        );
      }
      if (i > 0) {
        slivers.add(
          SliverToBoxAdapter(
            child: _SectionPassageDot(
              index: i - 1,
              pulseListenable: _sectionPassagePulse,
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
              onToggleMore: () => notifier.toggleMore(section),
              onTapArticle: (a) => _openArticle(context, a),
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
              onTapFavorite:
                  isFavorite ? () => showTourneeComposerSheet(context) : null,
              // Story 23.4 — bouton réglages (tune) sur la section veille →
              // ouvre la config en édition. Réutilisé par le CTA d'état vide.
              onTapSettings: section.kind == SectionKind.veille
                  ? () => context.push('${RoutePaths.veilleConfig}?mode=edit')
                  : null,
              // Tournée bugs E2E — CTA « Ajouter des sources » de l'empty-state
              // d'une section thème favorite vide → ouvre « Composer ma Tournée ».
              onAddSources: section is FeedThemeSection &&
                      section.kind == SectionKind.theme
                  ? () => showTourneeComposerSheet(context)
                  : null,
              onSeeAll: section is FeedThemeSection
                  ? (section.kind == SectionKind.source
                      ? () => _openSourceSection(context, section)
                      : () => _openThemeSection(context, section))
                  : section is DigestTopicSection
                      ? () => _openDigestSection(context, section)
                      : null,
            ),
          ),
        ),
      );
      // Grille rendue immédiatement après « Actus du jour » (identité robuste :
      // DigestTopicSection kind essentiel). Sliver séparé, hors du KeyedSubtree
      // — pas de GlobalKey, n'altère pas l'indexation _sectionKeys.
      if (section is DigestTopicSection &&
          section.kind == SectionKind.essentiel) {
        slivers.add(_grilleSliver);
      }
    }
    return slivers;
  }
}

/// Mutable, stable holder of the section framing offsets shared between the
/// screen state and the (immutable) [_SectionSnapPhysics]. The physics reads
/// [values] live each ballistic build; the state owns the writes.
class _SnapAnchors {
  List<SectionFrame> values = const [];
}

/// Scroll physics that folds a section-anchored snap into the fling's ballistic
/// phase. The platform parent (Bouncing iOS / Clamping Android) is preserved
/// via [applyTo], so `naturalLanding` inherits the native deceleration and the
/// snap is intrinsically un-gated by speed — it triggers on slow *and* fast
/// gestures.
class _SectionSnapPhysics extends ScrollPhysics {
  final _SnapAnchors anchors;

  const _SectionSnapPhysics({
    required this.anchors,
    super.parent,
  });

  @override
  _SectionSnapPhysics applyTo(ScrollPhysics? ancestor) {
    return _SectionSnapPhysics(
      anchors: anchors,
      parent: buildParent(ancestor),
    );
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final natural = super.createBallisticSimulation(position, velocity);
    final target = _resolveTarget(position, velocity, natural);
    if (target == null) return natural;
    return ScrollSpringSimulation(
      kSnapSpring,
      position.pixels,
      target,
      velocity,
      tolerance: toleranceFor(position),
    );
  }

  /// Resolves the clamped section-framed resting position, or `null` to keep
  /// the natural fling (header zone, free inside a tall section, already
  /// aligned, or no frames).
  double? _resolveTarget(
    ScrollMetrics position,
    double velocity,
    Simulation? natural,
  ) {
    final list = anchors.values;
    if (list.isEmpty) return null;
    // Let the platform overscroll own the hard edges. At the bottom of the feed
    // (notably under "Fin de tournée"), forcing our section spring on top of
    // iOS' bounce creates stepped rebounds and repeated settle haptics.
    if (position.outOfRange ||
        (position.pixels >= position.maxScrollExtent - kSnapEpsilon &&
            velocity >= 0)) {
      return null;
    }
    // Header/banner zone (above the first section) → let the RefreshIndicator
    // own pull-to-refresh; never snap.
    if (position.pixels <= list.first.top) return null;

    final landing =
        natural == null ? position.pixels : _simulationEndX(natural, position);
    if (landing <= 0) return null;

    // Travel direction from the controller, not the lift velocity: a slow
    // drag-to-read down ends at ≈ 0 velocity, which would misread as "going
    // up". ScrollDirection.reverse = scrolling down (offset increasing) ⇒ +1;
    // .forward = up ⇒ -1.
    final scrollDirection = position is ScrollPosition
        ? switch (position.userScrollDirection) {
            ScrollDirection.reverse => 1.0,
            ScrollDirection.forward => -1.0,
            ScrollDirection.idle => 0.0,
          }
        : 0.0;

    final raw = resolveSnapTarget(
      currentPixels: position.pixels,
      naturalLanding: landing,
      velocity: velocity,
      scrollDirection: scrollDirection,
      frames: list,
    );
    if (raw == null) return null;

    final clamped = raw.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((clamped - position.pixels).abs() <= kSnapEpsilon) return null;
    return clamped;
  }
}

/// Estimates the resting position of a ballistic [sim] by sampling it forward
/// until it reports done (capped). Honours the platform deceleration baked into
/// [sim] rather than re-deriving a friction model.
double _simulationEndX(Simulation sim, ScrollMetrics position) {
  var last = position.pixels;
  for (var t = 0.0; t <= 10.0; t += 1 / 60) {
    final x = sim.x(t);
    if (x.isNaN) break;
    last = x;
    if (sim.isDone(t)) break;
  }
  return last;
}

class _SectionPassagePulse {
  final int index;
  final int sequence;

  const _SectionPassagePulse({required this.index, required this.sequence});
}

class _SectionPassageDot extends StatefulWidget {
  final int index;
  final ValueListenable<_SectionPassagePulse?> pulseListenable;

  _SectionPassageDot({
    required this.index,
    required this.pulseListenable,
  }) : super(key: ValueKey('section_passage_dot_$index'));

  @override
  State<_SectionPassageDot> createState() => _SectionPassageDotState();
}

class _SectionPassageDotState extends State<_SectionPassageDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  int _lastSequence = -1;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    widget.pulseListenable.addListener(_onPulse);
  }

  @override
  void didUpdateWidget(_SectionPassageDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pulseListenable != widget.pulseListenable) {
      oldWidget.pulseListenable.removeListener(_onPulse);
      widget.pulseListenable.addListener(_onPulse);
    }
  }

  @override
  void dispose() {
    widget.pulseListenable.removeListener(_onPulse);
    _pulseController.dispose();
    super.dispose();
  }

  void _onPulse() {
    final pulse = widget.pulseListenable.value;
    if (pulse == null || pulse.index != widget.index) return;
    if (pulse.sequence == _lastSequence) return;
    _lastSequence = pulse.sequence;
    _pulseController
      ..stop()
      ..value = 0
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final dotColor = context.isDarkMode
        ? Colors.white.withValues(alpha: 0.42)
        : Colors.black.withValues(alpha: 0.34);
    return Semantics(
      label: 'Passage de section',
      child: SizedBox(
        height: 36,
        child: Align(
          alignment: const Alignment(0, -0.68),
          child: AnimatedBuilder(
            animation: _pulseController,
            builder: (context, _) {
              final t = Curves.easeOutCubic.transform(_pulseController.value);
              final scale =
                  1 + (0.30 * (1 - (2 * t - 1).abs()).clamp(0.0, 1.0));
              final glow = (1 - t).clamp(0.0, 1.0);
              return Transform.scale(
                scale: scale,
                child: Container(
                  width: 2.5,
                  height: 2.5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor.withValues(alpha: 0.76 + 0.14 * glow),
                    boxShadow: [
                      BoxShadow(
                        color: dotColor.withValues(alpha: 0.13 * glow),
                        blurRadius: 5,
                        spreadRadius: 0.5,
                      ),
                    ],
                    border: Border.all(
                      color: colors.backgroundPrimary.withValues(alpha: 0.78),
                      width: 0.75,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _StickyHostOverlay extends StatelessWidget {
  final ValueNotifier<bool> stickyVisible;
  final ValueNotifier<double> scrollProgress;
  final ValueNotifier<int> activeIndex;

  /// Descripteurs d'onglets (label+accent) dans l'ordre des slivers, calculés
  /// par [_FluxContinuScreenState._syncStickyEntries] — source unique partagée
  /// avec les clés du suivi actif, pour éviter tout recalcul divergent ici.
  final List<StickyTab> tabs;
  final ValueChanged<int> onTapTab;
  final ScrollController tabsController;

  const _StickyHostOverlay({
    required this.stickyVisible,
    required this.scrollProgress,
    required this.activeIndex,
    required this.tabs,
    required this.onTapTab,
    required this.tabsController,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: ValueListenableBuilder<bool>(
        valueListenable: stickyVisible,
        builder: (context, visible, _) {
          final showSticky = visible && tabs.isNotEmpty;
          if (!showSticky) {
            return const SizedBox.shrink();
          }
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
