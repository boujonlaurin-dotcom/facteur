import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart'
    show ValueListenable, defaultTargetPlatform, setEquals, TargetPlatform;
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
import '../providers/tournee_order_prefs_provider.dart'
    show tourneeOrderPrefsProvider;
import '../utils/section_snap.dart';
import '../widgets/citation_du_jour_card.dart';
import '../widgets/closing_card_v18.dart';
import '../widgets/flux_continu_article_card.dart';
import '../widgets/my_interests_intro.dart';
import '../widgets/personalisation_cta_card.dart';
import '../widgets/tournee_composer_sheet.dart';
import '../widgets/geoloc_prompt_banner.dart';
import '../widgets/section_block.dart';
import '../widgets/sticky_tab_bar.dart';
import '../../grille/widgets/grille_cta_card.dart';

/// Scroll offset at which the AppBar is swapped with the sticky tab bar.
const double _kStickyThreshold = 60.0;

/// Vertical offset the sticky bar consumes — used as a landing buffer
/// when scrolling a section into view so its banner doesn't disappear
/// behind the bar. Trimmed from 90 → 54 after the head title (~36px) was
/// dropped from the sticky overlay: tabs row (48) + progress track (4) + a
/// couple px of slack.
const double _kStickyBarHeight = 54.0;

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

/// Drag-time feedforward payload for [_SectionPassageDot]. Computed live in
/// [_FluxContinuScreenState._updateBoundaryApproach] and broadcast via a
/// [ValueNotifier] so the dots rebuild without a per-frame `setState`.
/// - [dotIndex] : the passage dot sitting at the boundary the gesture is
///   approaching (= the section index *before* it, same `k-1` convention as
///   [_FluxContinuScreenState._pulsePassageForStickyIndex]), or `null` when the
///   next snap point in the travel direction is **not** an inter-section
///   boundary (a tall section's free-reading bottom) — so no « va snapper » cue
///   appears inside the free interior, matching the physics which returns `null`
///   there too.
/// - [proximity] : ramps 0→1 as the lift point nears that boundary, reaching 1
///   exactly at [kSectionEdgeMargin] (the deadband where the snap commits), so
///   the dot peaks precisely at the switch threshold.
typedef _BoundaryApproach = ({int? dotIndex, double proximity});

/// Signed *travel* direction from a [ScrollDirection]: +1 scrolling down (offset
/// increasing), -1 up, 0 idle/unknown. Single mapping shared by the drag-time
/// feedforward ([_FluxContinuScreenState._updateBoundaryApproach]) and the snap
/// physics ([_SectionSnapPhysics._resolveTarget]) so the cue and the commit can
/// never disagree on « which way am I going ».
double _travelDirection(ScrollDirection d) => switch (d) {
      ScrollDirection.reverse => 1.0,
      ScrollDirection.forward => -1.0,
      ScrollDirection.idle => 0.0,
    };

class FluxContinuScreen extends ConsumerStatefulWidget {
  const FluxContinuScreen({super.key});

  @override
  ConsumerState<FluxContinuScreen> createState() => _FluxContinuScreenState();
}

class _FluxContinuScreenState extends ConsumerState<FluxContinuScreen> {
  final ScrollController _scroll = ScrollController();
  final ScrollController _tabsScroll = ScrollController();
  final ValueNotifier<bool> _stickyVisible = ValueNotifier(false);
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

  /// Sliver « Grille du jour » (carte d'entrée de La Grille). Son insertion est
  /// pilotée par `FluxContinuState.grilleSlotIndex`. Wrappé dans un
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

  /// Drag-time « distance to the next boundary » cue, written by
  /// [_updateBoundaryApproach] on every scroll frame (quantized) and read by the
  /// in-flow [_SectionPassageDot]s. Feedforward twin of [_sectionPassagePulse]
  /// (the post-validation pulse) — both ride the same dot so the gesture reads
  /// as a single continuous « j'approche un seuil → je l'ai franchi ».
  final ValueNotifier<_BoundaryApproach?> _boundaryApproach =
      ValueNotifier(null);

  /// Sorted snap points of [_snapAnchors], cached once per layout (frames only
  /// change on layout, never per scroll frame) so the per-frame
  /// [_updateBoundaryApproach] doesn't re-allocate + re-sort them every frame.
  List<double> _snapPoints = const [];

  /// Maps a section *top* (an inter-section boundary) to the passage dot above
  /// it (section index − 1). Rebuilt alongside the snap anchors in
  /// [_recomputeSnapAnchors]; [_updateBoundaryApproach] looks up an approached
  /// snap point here directly (the offsets are bit-identical to the stored
  /// frame tops). Tops absent here (a tall section's bottom, the first section,
  /// the virtual cards) carry no « va snapper » cue.
  final Map<double, int> _dotIndexByTop = {};

  /// (A3) Indices (into `state.sections`) of sections taller than the viewport —
  /// the ones with a free-reading interior (`bottom > top`, same predicate as
  /// the physics' free zone). Drives the [_FreeReadEdgeFade] « lecture libre »
  /// signifier. Rebuilt in [_recomputeSnapAnchors].
  final ValueNotifier<Set<int>> _tallSections = ValueNotifier(const {});

  /// Total bottom overlay height (app nav bar + system insets), captured from
  /// [MediaQuery.paddingOf] in [build]. With [extendBody: true] on the outer
  /// Scaffold, padding.bottom reflects the actual rendered height of
  /// [MainBottomNav] (50 dp content + SafeArea bottom padding), so it adapts
  /// automatically when the Android navigation bar raises the footer.
  /// Read in [_recomputeSnapAnchors] (post-frame callback — direct MediaQuery
  /// reads are unsafe there).
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
    _activeIndex.dispose();
    _sectionPassagePulse.dispose();
    _boundaryApproach.dispose();
    _tallSections.dispose();
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
    _updateActiveSection();
    _updateBoundaryApproach(pos);

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

  /// (A1) Feedforward: as the reader drags toward a section boundary, ramp the
  /// in-flow passage dot that sits there so the snap reads as « j'approche un
  /// seuil marqué » *before* the finger lifts — not a post-hoc surprise. Runs
  /// inside [_onScroll] (already firing every frame); reuses the live snap
  /// anchors and the shared [snapPointsOf], so the cue is mechanically true to
  /// where the snap commits. Cheap: writes a quantized value to
  /// [_boundaryApproach] only when it changes.
  void _updateBoundaryApproach(ScrollPosition pos) {
    final points = _snapPoints;
    final currentScroll = pos.pixels;
    // Header zone (above the first section): the sticky is hidden anyway ⇒ no
    // boundary cue.
    if (points.isEmpty || currentScroll <= points.first) {
      if (_boundaryApproach.value != null) _boundaryApproach.value = null;
      return;
    }
    // Travel direction (shared mapping with the physics). On idle, keep the
    // previous value so a pause mid-drag doesn't flicker the cue off.
    final dir = _travelDirection(pos.userScrollDirection);
    if (dir == 0) return;

    // The next snap point strictly in the travel direction.
    double? edge;
    if (dir > 0) {
      for (final p in points) {
        if (p > currentScroll + kSnapEpsilon) {
          edge = p;
          break;
        }
      }
    } else {
      for (var i = points.length - 1; i >= 0; i--) {
        if (points[i] < currentScroll - kSnapEpsilon) {
          edge = points[i];
          break;
        }
      }
    }
    if (edge == null) {
      if (_boundaryApproach.value != null) _boundaryApproach.value = null;
      return;
    }

    // Proximity ramps to 1 across the deadband where the snap commits, so the
    // dot peaks exactly at the switch threshold. The cue rides a dot only when
    // the approached point is an inter-section boundary (present in
    // [_dotIndexByTop]); a tall section's bottom maps to null ⇒ no « va snapper »
    // cue inside the free interior.
    final dist = (edge - currentScroll).abs();
    final proximity = (1 - dist / kSectionEdgeMargin).clamp(0.0, 1.0);
    // Quantize (~20 steps) so the small dot rebuilds only a handful of times
    // per gesture rather than every frame.
    final quantized = (proximity * 20).round() / 20;
    final next = (dotIndex: _dotIndexByTop[edge], proximity: quantized);
    final cur = _boundaryApproach.value;
    if (cur == null ||
        cur.dotIndex != next.dotIndex ||
        cur.proximity != next.proximity) {
      _boundaryApproach.value = next;
    }
  }

  Future<void> _triggerSectionChangeHaptic() async {
    try {
      await Haptics.vibrate(HapticsType.medium, usage: HapticsUsage.touch);
    } catch (_) {
      await HapticFeedback.mediumImpact();
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
      _snapPoints = const [];
      _dotIndexByTop.clear();
      _tallSections.value = const {};
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
    final visibleBottom = scrollBox.size.height - _safeAreaBottom;
    final result = <SectionFrame>[];
    _dotIndexByTop.clear();
    final tall = <int>{};
    for (var k = 0; k < _stickyEntryKeys.length; k++) {
      final ctx = _stickyEntryKeys[k].currentContext;
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
      // Map this entry to its real section index (virtual cards ⇒ −1) for the
      // A1 passage-dot cue and the A3 free-read fade. Same convention as
      // [_pulsePassageForStickyIndex].
      final sectionIndex = _sectionIndexForStickyIndex(k);
      if (sectionIndex > 0) {
        _dotIndexByTop[top] = sectionIndex - 1;
      }
      if (sectionIndex >= 0 && bottom > top + kSnapEpsilon) {
        tall.add(sectionIndex);
      }
    }
    result.sort((a, b) => a.top.compareTo(b.top));
    _snapAnchors.values = result;
    _snapPoints = snapPointsOf(result);
    if (!setEquals(_tallSections.value, tall)) {
      _tallSections.value = tall;
    }
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
    // Source unique : aligne [_sectionKeys] + [_stickyEntryKeys] sur les slivers
    // et dérive les descripteurs d'onglets (label+accent), dans le même ordre.
    final stickyTabs = _syncStickyEntries(state.valueOrNull);
    // Sections don't resize mid-session, so we refresh the snap anchors only on
    // these content/layout-driven rebuilds — never per scroll frame.
    _safeAreaBottom = MediaQuery.paddingOf(context).bottom;
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
  List<StickyTab> _syncStickyEntries(FluxContinuState? state) {
    if (state == null) {
      _stickyEntryKeys.clear();
      return const [];
    }
    if (_sectionKeys.length != state.sections.length) {
      _sectionKeys
        ..clear()
        ..addAll(List.generate(state.sections.length, (_) => GlobalKey()));
    }
    final citationPresent = state.quote != null && !state.closingDismissed;
    final grilleSlotIndex = state.grilleSlotIndex;

    final keys = <GlobalKey>[];
    final tabs = <StickyTab>[];
    void add(GlobalKey key, StickyTab tab) {
      keys.add(key);
      tabs.add(tab);
    }

    for (var i = 0; i < state.sections.length; i++) {
      if (grilleSlotIndex == i) {
        add(_grilleKey, _motDuJourTab);
      }
      final section = state.sections[i];
      add(
        _sectionKeys[i],
        StickyTab(label: section.label, accent: section.accent),
      );
    }
    if (grilleSlotIndex == state.sections.length) {
      add(_grilleKey, _motDuJourTab);
    }
    if (citationPresent) {
      add(_citationKey, _citationTab);
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
            parent: _SectionSnapPhysics(anchors: _snapAnchors),
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
            if (state.sections.isEmpty && state.grilleSlotIndex == null)
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
    final favoriteCount = state.sections.where(_isFavoriteSection).length;
    final swipeLeftHintSeen =
        ref.watch(swipeLeftHintSeenProvider).valueOrNull ?? true;

    // Story Essentiel UX — la carte de perso (compte non personnalisé) et
    // l'inline « Gérer / Tes N favoris » (compte personnalisé) s'excluent.
    final customized =
        ref.watch(tourneeOrderPrefsProvider.select((s) => s.customized));
    final heroPresent =
        state.sections.isNotEmpty && state.sections.first is EssentielSection;
    // Cible de l'inline (mode personnalisé) : la 1ʳᵉ section de contenu après le
    // hero. On l'embarque DANS le `KeyedSubtree` de cette section pour que son
    // ancre de snap inclue l'inline — il n'est plus orphelin « entre deux
    // snaps ». -1 = pas de cible (aucune section après le hero).
    final inlineTargetIndex = heroPresent
        ? (state.sections.length > 1 ? 1 : -1)
        : (state.sections.isNotEmpty ? 0 : -1);

    final slivers = <SliverToBoxAdapter>[];
    for (var i = 0; i < state.sections.length; i++) {
      if (state.grilleSlotIndex == i) {
        slivers.add(_grilleSliver);
      }
      if (i > 0) {
        slivers.add(
          SliverToBoxAdapter(
            child: _SectionPassageDot(
              index: i - 1,
              pulseListenable: _sectionPassagePulse,
              approachListenable: _boundaryApproach,
            ),
          ),
        );
      }
      final section = state.sections[i];
      final isFavorite = _isFavoriteSection(section);
      // Mode personnalisé : préfixe l'inline « Gérer / Tes N favoris » au-dessus
      // du `SectionBlock`, à l'intérieur du subtree mesuré → l'inline fait
      // partie du bloc de snap de cette section (cf. [inlineTargetIndex]).
      final showInlineHere = customized && i == inlineTargetIndex;
      slivers.add(
        SliverToBoxAdapter(
          child: KeyedSubtree(
            key: _sectionKeys[i],
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showInlineHere)
                  MyInterestsIntro(
                    favoriteCount: favoriteCount,
                    onTapManage: () => showTourneeComposerSheet(context),
                  ),
                _FreeReadEdgeFade(
                  index: i,
                  tallSections: _tallSections,
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
                    onTapFavorite: isFavorite
                        ? () => showTourneeComposerSheet(context)
                        : null,
                    // Story 23.4 — bouton réglages (tune) sur la section veille →
                    // ouvre la config en édition. Réutilisé par le CTA d'état vide.
                    onTapSettings: section.kind == SectionKind.veille
                        ? () =>
                            context.push('${RoutePaths.veilleConfig}?mode=edit')
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
              ],
            ),
          ),
        ),
      );
      // Compte non personnalisé : carte de perso dédiée juste après le hero
      // (son propre bloc de snap — destination volontaire), à la place de
      // l'inline. Une fois personnalisée, c'est l'inline qui reprend (cf.
      // [showInlineHere]).
      if (!customized && heroPresent && i == 0) {
        slivers.add(
          const SliverToBoxAdapter(child: PersonalisationCtaCard()),
        );
      }
    }
    if (state.grilleSlotIndex == state.sections.length) {
      slivers.add(_grilleSliver);
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

  const _SectionSnapPhysics({required this.anchors, super.parent});

  @override
  _SectionSnapPhysics applyTo(ScrollPhysics? ancestor) {
    return _SectionSnapPhysics(anchors: anchors, parent: buildParent(ancestor));
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
    // up". Shared mapping with the drag-time feedforward via [_travelDirection].
    final scrollDirection = position is ScrollPosition
        ? _travelDirection(position.userScrollDirection)
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

  /// (A1) Drag-time feedforward: when `value.dotIndex == index`, the dot grows
  /// and brightens with `value.proximity` *before* the snap commits, fusing
  /// feedforward and the post-validation [pulseListenable] pulse in one object.
  final ValueListenable<_BoundaryApproach?> approachListenable;

  _SectionPassageDot({
    required this.index,
    required this.pulseListenable,
    required this.approachListenable,
  }) : super(key: ValueKey('section_passage_dot_$index'));

  @override
  State<_SectionPassageDot> createState() => _SectionPassageDotState();
}

class _SectionPassageDotState extends State<_SectionPassageDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  /// Cached rebuild trigger (pulse OR drag-approach) so the merged listenable
  /// isn't re-allocated on every build. Rebuilt only if [approachListenable]
  /// identity changes.
  late Listenable _repaint;
  int _lastSequence = -1;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _repaint = Listenable.merge([_pulseController, widget.approachListenable]);
    widget.pulseListenable.addListener(_onPulse);
  }

  @override
  void didUpdateWidget(_SectionPassageDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pulseListenable != widget.pulseListenable) {
      oldWidget.pulseListenable.removeListener(_onPulse);
      widget.pulseListenable.addListener(_onPulse);
    }
    if (oldWidget.approachListenable != widget.approachListenable) {
      _repaint =
          Listenable.merge([_pulseController, widget.approachListenable]);
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
            // Rebuild on either the post-validation pulse OR the drag-time
            // approach cue — both feed the same dot (cached merged listenable).
            animation: _repaint,
            builder: (context, _) {
              final t = Curves.easeOutCubic.transform(_pulseController.value);
              final pulseBump = 0.30 * (1 - (2 * t - 1).abs()).clamp(0.0, 1.0);
              final glow = (1 - t).clamp(0.0, 1.0);
              // Feedforward proximity (0 when this dot isn't the one being
              // approached). Folded into the same scale/alpha/shadow as the
              // pulse so the two cues read as one continuous gesture.
              final approach = widget.approachListenable.value;
              final proximity =
                  (approach != null && approach.dotIndex == widget.index)
                      ? approach.proximity
                      : 0.0;
              final scale = 1 + pulseBump + 0.9 * proximity;
              final fillAlpha = (0.76 + 0.14 * glow + 0.20 * proximity).clamp(
                0.0,
                1.0,
              );
              return Transform.scale(
                scale: scale,
                child: Container(
                  width: 2.5,
                  height: 2.5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor.withValues(alpha: fillAlpha),
                    boxShadow: [
                      BoxShadow(
                        color: dotColor.withValues(
                          alpha: 0.13 * glow + 0.30 * proximity,
                        ),
                        blurRadius: 5 + 4 * proximity,
                        spreadRadius: 0.5 + proximity,
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

/// (A3) « Carte haute = lecture libre » signifier. A section taller than the
/// viewport (its index is in [tallSections]) gets a subtle bottom fade
/// (`backgroundPrimary` → transparent, ~24 px), reading as « ce contenu coule
/// sous le bord, tu peux scroller librement » — coherent with the physics
/// leaving that interior un-snapped and with A1 emitting no « va snapper » dot
/// there. Short/snapping sections render the child untouched. Painted by the
/// screen (Stack overlay) so [SectionBlock]'s signature stays unchanged.
class _FreeReadEdgeFade extends StatelessWidget {
  final int index;
  final ValueListenable<Set<int>> tallSections;
  final Widget child;

  const _FreeReadEdgeFade({
    required this.index,
    required this.tallSections,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<int>>(
      valueListenable: tallSections,
      child: child,
      builder: (context, tall, child) {
        if (!tall.contains(index)) return child!;
        final base = context.facteurColors.backgroundPrimary;
        return Stack(
          children: [
            child!,
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 24,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [base.withValues(alpha: 0), base],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StickyHostOverlay extends StatelessWidget {
  final ValueNotifier<bool> stickyVisible;
  final ValueNotifier<int> activeIndex;

  /// Descripteurs d'onglets (label+accent) dans l'ordre des slivers, calculés
  /// par [_FluxContinuScreenState._syncStickyEntries] — source unique partagée
  /// avec les clés du suivi actif, pour éviter tout recalcul divergent ici.
  final List<StickyTab> tabs;
  final ValueChanged<int> onTapTab;
  final ScrollController tabsController;

  const _StickyHostOverlay({
    required this.stickyVisible,
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
          // The progress track is now segmented and driven solely by the
          // discrete active index — no continuous scroll-fraction needed.
          return ValueListenableBuilder<int>(
            valueListenable: activeIndex,
            builder: (context, idx, _) => StickyTabBar(
              tabs: tabs,
              activeIndex: idx.clamp(0, tabs.length - 1),
              onTapTab: onTapTab,
              tabsController: tabsController,
              showFilterBar: false,
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
