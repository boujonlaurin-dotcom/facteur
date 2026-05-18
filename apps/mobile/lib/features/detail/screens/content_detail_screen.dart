import 'package:cached_network_image/cached_network_image.dart';
import 'package:facteur/core/utils/html_utils.dart';
import 'package:flutter/foundation.dart'
    show Factory, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'dart:async';
import 'dart:math' as math;

import '../../../config/theme.dart';
import '../../../config/topic_labels.dart';
import '../../../core/api/api_client.dart';
import '../../../core/providers/analytics_provider.dart';
import '../../feed/models/content_model.dart';
import '../../../core/providers/navigation_providers.dart';
import '../../feed/providers/feed_provider.dart';
import '../../feed/repositories/feed_repository.dart';
import '../../feed/widgets/perspectives_bottom_sheet.dart';
import '../../my_interests/models/user_interests_state.dart' show InterestState;
import '../../my_interests/providers/user_sources_state_provider.dart';
import '../../sources/providers/sources_providers.dart';
import '../../sources/widgets/source_logo_avatar.dart';
import '../../../widgets/sunflower_icon.dart';
import '../providers/nudge_provider.dart' show NudgeTracker;
import '../widgets/article_reader_widget.dart';
import '../widgets/audio_player_widget.dart';
import '../widgets/youtube_player_widget.dart';
import '../widgets/note_input_sheet.dart';
import '../../../core/nudges/nudge_coordinator.dart';
import '../../../core/nudges/nudge_counters.dart';
import '../../../core/nudges/nudge_ids.dart';
import '../../../core/nudges/widgets/nudge_inline_banner.dart';
import '../../custom_topics/widgets/topic_chip.dart';
import '../../digest/widgets/editorial_badge.dart';
import '../../custom_topics/providers/custom_topics_provider.dart';
import '../../../core/ui/notification_service.dart';
import '../../saved/widgets/collection_picker_sheet.dart';
import '../../saved/providers/collections_provider.dart';
import '../../../widgets/design/facteur_thumbnail.dart';

/// Écran de détail d'un contenu avec mode lecture In-App (Story 5.2)
/// Restauré avec les fonctionnalités de l'ancien ArticleViewerModal :
/// - Badge de biais politique
/// - Indicateur de fiabilité
/// - Bouton "Comparer" (perspectives)
/// - Analytics tracking
/// - Bookmark toggle
/// - Note sur article (Story Notes)
class ContentDetailScreen extends ConsumerStatefulWidget {
  final String contentId;
  final Content? content; // Passed via extra from GoRouter

  const ContentDetailScreen({
    super.key,
    required this.contentId,
    this.content,
  });

  @override
  ConsumerState<ContentDetailScreen> createState() =>
      _ContentDetailScreenState();
}

/// Height of the header content area (below the status bar).
/// = top padding (16) + icon row (~36) + bottom padding (8) + 2px safety margin.
const double _kHeaderContentHeight = 62;

/// Visual bottom of the header for overlay anchoring (progress bar, sticky headers).
/// Slightly less than the true bottom to guarantee 1px overlap and eliminate rounding gaps.
const double _kHeaderVisualBottom = 59;

/// Height of the footer content area (above the safe-area bottom inset).
/// = vertical padding (12+12) + button row height (44).
const double _kFooterContentHeight = 82.0;

class _ContentDetailScreenState extends ConsumerState<ContentDetailScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _bookmarkBounceController;
  late Animation<double> _bookmarkScaleAnimation;
  late AnimationController _likeBounceController;
  late Animation<double> _likeScaleAnimation;
  late AnimationController _exitAnimController;
  bool _isExitAnimating = false;

  bool _isShortArticle = false;
  // true once user reaches end of displayed content
  final ValueNotifier<bool> _footerPermanent = ValueNotifier<bool>(false);
  bool _showReadOnSiteNudge = false;
  int _articleOpenCount = 0;
  bool _readOnSiteNudgeRequested = false;

  AnimationController? _perspectivesPulseController;
  Animation<double>? _perspectivesPulseScale;
  bool _perspectivesCtaTriggered = false;
  bool _linkCopiedHeader = false;
  Timer? _linkCopiedHeaderTimer;
  bool _premiumRedirectScheduled = false;
  bool _webFallbackRedirectScheduled = false;
  late DateTime _startTime;
  WebViewController? _webViewController;
  // Mutable: flipped to `true` from `_onReadOnSiteTap` when the in-app
  // reader could not enter scroll-to-site mode (htmlContent missing or
  // too short on Android race conditions). Forces `_buildWebViewFallback`
  // to render and prevents an unwanted external browser jump.
  bool _showWebView = false;

  // Scroll-to-site state
  final ScrollController _scrollController = ScrollController();
  // In-app reader scroll controller (separate from scroll-to-site)
  final ScrollController _inAppScrollController = ScrollController();
  final GlobalKey _articleKey = GlobalKey();
  final GlobalKey _bridgeKey = GlobalKey();
  final GlobalKey _perspectivesKey = GlobalKey();
  bool _isWebViewActive = false;
  bool _ctaTapped = false;
  double _bridgeEndOffset = 0;
  bool _offsetsComputed = false;
  // Once the WebView fade-in completes, drop the heavy article subtree from
  // the tree so Flutter no longer rasterizes/composites it on top of the
  // scrolling WebView (eliminates per-frame UI-thread cost).
  bool _articleLayerMounted = true;
  Timer? _articleLayerUnmountTimer;

  Timer? _readingTimer;
  Timer? _noteNudgeTimer;
  Timer? _scrollStopTimer;
  // 🌻 Nudge "Recommander ?" state
  Timer? _sunflowerNudgeTimer;
  bool _showSunflowerNudge = false;
  Timer? _inactivityTimer;
  double _webScrollY = 0.0;
  late AnimationController _headerAutoController;
  double _headerAutoStart = 0.0;
  double _headerAutoTarget = 0.0;

  /// Header slide offset as a fraction: 0.0 = fully visible, 1.0 = fully hidden.
  final ValueNotifier<double> _headerOffset = ValueNotifier<double>(0.0);
  bool _isConsumed = false;
  bool _hasOpenedNote = false;
  static const int _consumptionThreshold = 30; // seconds
  static const int _noteNudgeDelay = 20; // seconds

  // Reading progress tracking (0.0 - 1.0)
  // Uses ValueNotifier to avoid rebuilding the entire widget tree on each scroll pixel.
  // _readingProgress reflects actual scroll position (moves forward and backward).
  // _maxReadingProgress tracks the high-water mark (for share FAB, analytics, etc).
  final ValueNotifier<double> _readingProgress = ValueNotifier<double>(0.0);
  double _maxReadingProgress = 0;

  // Keys and cached extent for article-only reading progress measurement
  final GlobalKey _articleEndKey = GlobalKey();
  final GlobalKey _scrollViewKey = GlobalKey();
  double? _articleContentExtent;

  // Footer slide offset: 0.0 = fully visible, 1.0 = fully hidden (mirrors _headerOffset)
  final ValueNotifier<double> _footerOffset = ValueNotifier<double>(0.0);
  double _footerAutoStart = 0.0;
  double _footerAutoTarget = 0.0;
  late AnimationController _footerAutoController;
  // Subtle scale-pop on the "Lire sur ..." CTA when it transitions to its
  // primary (orange) state — signals the user has reached the end.
  late AnimationController _ctaPulseController;

  // Video detail screen state
  bool _isDescriptionExpanded = false;

  Content? _content;
  bool _contentResolved = false;

  // Perspectives pill state
  PerspectivesResponse? _perspectivesResponse;
  bool _perspectivesLoading = false;

  // Perspectives analysis state (lifted from inline section)
  PerspectivesAnalysisState _perspectivesAnalysisState =
      PerspectivesAnalysisState.idle;
  String? _perspectivesAnalysisText;
  final GlobalKey _analysisZoneKey = GlobalKey();

  // Perspectives section state
  Set<String> _perspectivesSelectedSegments = {};
  bool _perspectivesExpanded = false;

  @override
  void initState() {
    super.initState();
    _content = widget.content;
    _startTime = DateTime.now();
    if (_content != null) {
      _isConsumed = _content!.status == ContentStatus.consumed;
    }
    // Always fetch fresh content to accept latest metadata/status/theme
    _fetchContent();

    // Auto-fetch perspectives for articles
    if (_content?.contentType == ContentType.article) {
      _fetchPerspectives();
    }

    // Bookmark bounce animation (triggered on first note character)
    _bookmarkBounceController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _bookmarkScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.3)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.3, end: 1.0)
            .chain(CurveTween(curve: Curves.bounceOut)),
        weight: 70,
      ),
    ]).animate(_bookmarkBounceController);

    // Like FAB bounce animation
    _likeBounceController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _likeScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.3)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.3, end: 1.0)
            .chain(CurveTween(curve: Curves.bounceOut)),
        weight: 70,
      ),
    ]).animate(_likeBounceController);

    _exitAnimController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _headerAutoController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _headerAutoController.addListener(() {
      _headerOffset.value = _headerAutoStart +
          (_headerAutoTarget - _headerAutoStart) * _headerAutoController.value;
    });

    _footerAutoController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _footerAutoController.addListener(() {
      _footerOffset.value = _footerAutoStart +
          (_footerAutoTarget - _footerAutoStart) * _footerAutoController.value;
    });

    _ctaPulseController = AnimationController(
      duration: const Duration(milliseconds: 280),
      vsync: this,
    );
    _footerPermanent.addListener(_onFooterPermanentChanged);

    WidgetsBinding.instance.addObserver(this);

    // Persist article open count for triggers (read_on_site 4th article,
    // feed_preview_longpress ≥2 articles opened).
    NudgeCounters.increment(NudgeCounters.articleOpenCount).then((count) {
      if (mounted) _articleOpenCount = count;
    });

    // 🌻 Nudge: record article open and start 30s timer
    NudgeTracker.recordArticleOpen();
    _sunflowerNudgeTimer = Timer(const Duration(seconds: 30), () async {
      if (!mounted) return;
      final isLiked = _content?.isLiked ?? false;
      final shouldShow = await NudgeTracker.shouldShowNudge(
        isAlreadySunflowered: isLiked,
      );
      if (shouldShow && mounted) {
        setState(() => _showSunflowerNudge = true);
        NudgeTracker.markNudgeShown();
        // Auto-dismiss after 5 seconds
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted) setState(() => _showSunflowerNudge = false);
        });
      }
    });

    // Start timer if content is suitable for in-app reading/viewing and not already consumed
    final isVideo = _content?.isVideo ?? false;
    if ((_content?.hasInAppContent == true || isVideo) && !_isConsumed) {
      _startReadingTimer();
    }

    // Note nudge: bounce merged bookmark FAB after 20s if user hasn't opened note
    _noteNudgeTimer = Timer(const Duration(seconds: _noteNudgeDelay), () {
      if (mounted && !_hasOpenedNote) {
        _bookmarkBounceController.forward(from: 0);
      }
    });

    // Scroll-to-site: attach scroll listener
    _scrollController.addListener(_onScrollToSite);

    // Reading progress: track scroll depth
    _scrollController.addListener(_onScrollReadingProgress);

    // End-of-article nudge: show contextual action when progress >= 90%
    _readingProgress.addListener(_onReadingProgressNudge);

    // Detect short articles after the first layout pass has had time to
    // render the article HTML. A naive postFrame callback fires before
    // `flutter_html` finishes laying out, which made long articles look
    // "short" (maxScrollExtent < 50) and locked the CTA orange on open.
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      _checkShortArticle();
    });

    // Pre-load WebView for articles
    _initScrollToSiteWebView();
  }

  /// Pre-load the WebView controller for progressive scroll-to-site.
  void _initScrollToSiteWebView() {
    final content = _content;
    if (content == null || kIsWeb) return;
    if (content.contentType != ContentType.article) return;
    if (!content.hasInAppContent) return;

    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => _injectScrollBridgeScript(),
      ))
      ..addJavaScriptChannel('ScrollBridge',
          onMessageReceived: _onScrollBridgeMessage)
      ..loadRequest(Uri.parse(content.url));
  }

  /// Inject JS to drive the reader chrome from finger gestures + track
  /// reading progress.
  ///
  /// The chrome (header/footer) is piloted **only** by `touchmove` deltas,
  /// never by `window.scrollY`. Site-driven scroll mutations (sticky-header
  /// collapse, lazy-load reflow, virtual scroll, …) emit `scroll` events
  /// without a matching `touchmove` and used to flicker the chrome; they
  /// are now ignored by construction. `window.scroll` is only observed for
  /// reading-progress and to mirror `scrollY` back to Dart (used by the
  /// inactivity timer).
  Future<void> _injectScrollBridgeScript() async {
    if (_webViewController == null) return;
    await _webViewController!.runJavaScript('''
      (function() {
        var lastTouchY = 0;
        var lastTouchT = 0;
        var velocity = 0;        // px/ms, smoothed (positive = finger moves down)
        var touchActive = false;
        var pendingDy = 0;       // accumulated finger Δy since last rAF flush
        var rafScheduled = false;
        var raf = window.requestAnimationFrame
          ? function(cb) { window.requestAnimationFrame(cb); }
          : function(cb) { setTimeout(cb, 16); };
        function flushGesture() {
          rafScheduled = false;
          var dy = pendingDy;
          pendingDy = 0;
          if (Math.abs(dy) < 1) return;
          // Invert sign so positive = page-scroll-down-equivalent (hide chrome).
          ScrollBridge.postMessage('gesture_delta:' + (-dy));
        }
        document.addEventListener('touchstart', function(e) {
          if (e.touches.length > 1) { touchActive = false; return; }
          lastTouchY = e.touches[0].clientY;
          lastTouchT = (window.performance && performance.now) ? performance.now() : Date.now();
          velocity = 0;
          pendingDy = 0;
          touchActive = true;
          ScrollBridge.postMessage('gesture_start');
        }, { passive: true });
        document.addEventListener('touchmove', function(e) {
          if (!touchActive || e.touches.length > 1) return;
          var y = e.touches[0].clientY;
          var t = (window.performance && performance.now) ? performance.now() : Date.now();
          var dy = y - lastTouchY;
          var dt = t - lastTouchT;
          if (dt > 0) {
            // Exponential moving average — keeps a stable read of finger speed
            // through the natural micro-jitter of touch sampling.
            velocity = 0.7 * velocity + 0.3 * (dy / dt);
          }
          lastTouchY = y;
          lastTouchT = t;
          pendingDy += dy;
          if (!rafScheduled) {
            rafScheduled = true;
            raf(flushGesture);
          }
        }, { passive: true });
        document.addEventListener('touchend', function(e) {
          if (!touchActive) return;
          touchActive = false;
          // Flush any pending pixel-fraction before the snap so the offset
          // is current.
          if (rafScheduled) flushGesture();
          // velocity is finger px/ms; invert sign (page-down equivalent) and
          // convert to px/s for the Dart snap heuristic.
          ScrollBridge.postMessage('gesture_end:' + (-velocity * 1000));
        }, { passive: true });
        document.addEventListener('touchcancel', function(e) {
          if (!touchActive) return;
          touchActive = false;
          if (rafScheduled) flushGesture();
          ScrollBridge.postMessage('gesture_cancel');
        }, { passive: true });
        // `window.scroll` is observed *only* for progress + scrollY mirroring.
        // It never drives the chrome offset.
        var lastProgress = 0;
        var progressTimer = null;
        var scrollYTimer = null;
        function flushProgress() {
          progressTimer = null;
          var maxScroll = document.documentElement.scrollHeight - window.innerHeight;
          if (maxScroll <= 0) return;
          var pct = parseFloat((window.scrollY / maxScroll * 100).toFixed(1));
          pct = Math.min(100, Math.max(0, pct));
          if (pct !== lastProgress) {
            lastProgress = pct;
            ScrollBridge.postMessage('progress:' + pct);
          }
        }
        function flushScrollY() {
          scrollYTimer = null;
          ScrollBridge.postMessage('scroll_y:' + window.scrollY);
        }
        window.addEventListener('scroll', function() {
          if (!scrollYTimer) scrollYTimer = setTimeout(flushScrollY, 100);
          if (!progressTimer) progressTimer = setTimeout(flushProgress, 300);
        }, { passive: true });
      })();
    ''');
  }

  /// Handle messages from the WebView JS bridge.
  void _onScrollBridgeMessage(JavaScriptMessage message) {
    final msg = message.message;
    if (msg == 'gesture_start') {
      _onGestureStart();
      return;
    }
    if (msg.startsWith('gesture_delta:')) {
      final delta = double.tryParse(msg.substring(14));
      if (delta != null) _onGestureDelta(delta);
      return;
    }
    if (msg.startsWith('gesture_end:')) {
      final vel = double.tryParse(msg.substring(12)) ?? 0;
      _onGestureEnd(vel);
      return;
    }
    if (msg == 'gesture_cancel') {
      _onGestureEnd(0);
      return;
    }
    if (msg.startsWith('scroll_y:')) {
      final y = double.tryParse(msg.substring(9));
      if (y != null) _webScrollY = y;
      return;
    }
    if (msg.startsWith('progress:')) {
      final pct = double.tryParse(msg.substring(9));
      if (pct != null) {
        // For partial content: WebView scroll maps to 25%-100% of total progress
        // For full content: WebView scroll maps to the full 0%-100%
        final double normalized;
        if (_isPartialContent) {
          normalized = 0.25 + (pct / 100.0) * 0.75;
        } else {
          normalized = pct / 100.0;
        }
        final clamped = normalized.clamp(0.0, 1.0);
        _readingProgress.value = clamped;
        if (clamped > _maxReadingProgress) {
          _maxReadingProgress = clamped;
        }
      }
    }
  }

  /// Whether the current article has only partial in-app content.
  bool get _isPartialContent {
    final c = _content;
    if (c == null) return false;
    final articleText = c.htmlContent ?? c.description;
    return isPartialContent(articleText);
  }

  /// Track in-app scroll depth for reading progress.
  /// For partial content, in-app scroll caps at 25% — WebView fills the rest.
  void _onScrollReadingProgress() {
    if (!_scrollController.hasClients) return;
    final maxExtent = _scrollController.position.maxScrollExtent;
    if (maxExtent <= 0) return;
    final pixels = _scrollController.offset;
    // Use article-only extent so the perspectives section doesn't dilute progress
    final articleExtent = _articleContentExtent ?? maxExtent;
    final rawProgress = pixels / articleExtent;
    final progress = _isPartialContent
        ? (rawProgress * 0.25).clamp(0.0, 0.25)
        : rawProgress.clamp(0.0, 1.0);
    _readingProgress.value = progress;
    if (progress > _maxReadingProgress) {
      _maxReadingProgress = progress;
    }
    _maybeRequestReadOnSiteNudge(progress);
  }

  void _maybeRequestReadOnSiteNudge(double progress) {
    if (_isPartialContent) return;
    if (_readOnSiteNudgeRequested) return;
    if (_showReadOnSiteNudge) return;
    if (progress < 0.5) return;
    if (_articleOpenCount < 4) return;
    _readOnSiteNudgeRequested = true;
    _requestReadOnSiteNudge();
  }

  Future<void> _requestReadOnSiteNudge() async {
    final coordinator = ref.read(nudgeCoordinatorProvider);
    final active = await coordinator.request(NudgeIds.articleReadOnSite);
    if (!mounted) return;
    if (active == NudgeIds.articleReadOnSite) {
      setState(() => _showReadOnSiteNudge = true);
    }
  }

  Future<void> _dismissReadOnSiteNudge({required bool converted}) async {
    if (!_showReadOnSiteNudge) return;
    final coordinator = ref.read(nudgeCoordinatorProvider);
    if (coordinator.activeId == NudgeIds.articleReadOnSite) {
      if (converted) {
        await coordinator.markConverted(NudgeIds.articleReadOnSite);
      } else {
        await coordinator.dismiss(markSeen: true);
      }
    }
    if (mounted) {
      setState(() => _showReadOnSiteNudge = false);
    }
  }

  /// Show header + footer when user reaches the bottom of the article (progress ≥ 98%).
  /// Skipped in WebView mode — overlays are controlled by scroll direction only.
  void _onReadingProgressNudge() {
    if (_isWebViewActive) return;
    if (_readingProgress.value >= 0.98) {
      _inactivityTimer?.cancel();
      if (_headerOffset.value > 0.0) _animateHeaderTo(0.0);
      if (_footerOffset.value > 0.0) _animateFooterTo(0.0);
    }
  }

  /// Detect short articles that don't need scrolling.
  ///
  /// Latches `_isShortArticle` (and `_footerPermanent`) only when we are
  /// confident the article is genuinely short — i.e. the content is fully
  /// rendered AND its plain-text length is small. Latching too eagerly on
  /// the first frame caused long articles to appear "short" before
  /// `flutter_html` had finished laying out, leaving the CTA orange from
  /// the moment the screen opens.
  void _checkShortArticle() {
    if (_isShortArticle) return;
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.maxScrollExtent >= 50) return;

    final article = _content;
    if (article != null && article.contentType == ContentType.article) {
      final text = article.htmlContent ?? article.description;
      // Bail out: if the article carries any meaningful text, the small
      // maxScrollExtent only means the HTML hasn't laid out yet — wait.
      if (plainTextLength(text) >= 200) return;
    }

    _isShortArticle = true;
    _footerPermanent.value = true;
  }

  /// Fires a brief scale-pop on the primary CTA when `_footerPermanent`
  /// flips to true (i.e. the bouton "Lire sur ..." just turned orange).
  /// Skipped while in WebView mode where the orange state is unused.
  void _onFooterPermanentChanged() {
    if (!_footerPermanent.value) return;
    if (_isWebViewActive || _ctaTapped || _showWebView) return;
    HapticFeedback.selectionClick();
    _ctaPulseController.forward(from: 0.0);
  }

  /// Measures the pixel distance from the top of the scroll content to the
  /// end of the article section (before perspectives). Stored in
  /// [_articleContentExtent] so the progress bar ignores perspectives height.
  void _measureArticleExtent() {
    final endBox =
        _articleEndKey.currentContext?.findRenderObject() as RenderBox?;
    final svBox =
        _scrollViewKey.currentContext?.findRenderObject() as RenderBox?;
    if (endBox == null || svBox == null) return;
    if (!_scrollController.hasClients) return;
    // content-coord of marker = screen Y of marker − screen Y of sv top + scroll offset
    final extent = endBox.localToGlobal(Offset.zero).dy -
        svBox.localToGlobal(Offset.zero).dy +
        _scrollController.offset;
    if (extent > 0) _articleContentExtent = extent;
  }

  /// Compute the scroll offset threshold at which the WebView should activate.
  ///
  /// Derived from [ScrollPosition.maxScrollExtent] rather than from per-zone
  /// heights (article, perspectives, bridge). This guarantees the threshold is
  /// always reachable regardless of the Column layout — header spacer, article
  /// size, perspectives presence/height all get accounted for automatically.
  ///
  /// The old formula (`articleHeight + bridgeHeight`) ignored the top header
  /// spacer AND the perspectives section, making the threshold unreachable for
  /// articles without large perspectives (maxScrollExtent < threshold).
  void _computeScrollOffsets() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (!position.hasContentDimensions) return;

    final max = position.maxScrollExtent;
    if (max <= 0) return;

    // Activate WebView 8px before max scroll so overscroll bounce doesn't
    // flicker the latch between frames at the very end.
    _bridgeEndOffset = (max - 8).clamp(0.0, max);

    _offsetsComputed = true;
  }

  /// Shared handler for the inline "Couverture médiatique" toggle. On
  /// expand-from-collapsed, scrolls the section into view.
  void _onPerspectivesToggle() {
    HapticFeedback.lightImpact();
    final wasCollapsed = !_perspectivesExpanded;
    setState(() {
      _perspectivesExpanded = !_perspectivesExpanded;
    });
    if (wasCollapsed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final ctx = _perspectivesKey.currentContext;
        if (ctx == null) return;
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.0,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      });
    }
  }

  /// Toggles a perspectives bias-bar segment filter. Mirrors the logic in
  /// [_PerspectivesInlineSectionState._onSegmentTapInternal].
  void _onPerspectivesSegmentTap(String key) {
    setState(() {
      final current = _perspectivesSelectedSegments;
      if (current.contains(key)) {
        _perspectivesSelectedSegments =
            current.length == 1 ? {} : (Set.from(current)..remove(key));
      } else {
        _perspectivesSelectedSegments = current.isEmpty || current.length == 3
            ? {key}
            : (Set.from(current)..add(key));
      }
    });
  }

  /// Exit WebView mode and return to in-app article reading.
  void _exitWebViewMode() {
    setState(() {
      _isWebViewActive = false;
      _ctaTapped = false;
      _offsetsComputed = false;
      _bridgeEndOffset = 0;
    });
    _footerPermanent.value = false;
    _animateFooterTo(0.0);
    _scrollController.jumpTo(0);
  }

  /// Scroll listener driving WebView activation.
  void _onScrollToSite() {
    if (!_ctaTapped || !_offsetsComputed) return;

    // Re-measure on every scroll to handle late HTML rendering
    _computeScrollOffsets();

    final offset = _scrollController.offset;
    final shouldActivate = offset >= _bridgeEndOffset;

    // One-way latch: once WebView is active, never deactivate it.
    if (shouldActivate && !_isWebViewActive) {
      setState(() {
        _isWebViewActive = true;
      });
      // Drop the article subtree from the tree once the 300 ms fade-out is
      // done, so Flutter stops painting it under the scrolling WebView.
      _articleLayerUnmountTimer?.cancel();
      _articleLayerUnmountTimer =
          Timer(const Duration(milliseconds: 320), () {
        if (mounted && _isWebViewActive && _articleLayerMounted) {
          setState(() => _articleLayerMounted = false);
        }
      });
      // Reset permanent-footer latch acquired during the CTA reveal scroll
      // so subsequent WebView scroll deltas can hide/show header & footer.
      _footerPermanent.value = false;

      // Smart-arrival : libère l'écran pour que l'utilisateur puisse interagir
      // avec une éventuelle modale (cookies, paywall) qui verrouille souvent
      // body { overflow: hidden } — sans scroll, le ScrollBridge JS ne peut
      // rien signaler, donc on doit cacher proactivement les overlays.
      // Header reste toujours visible en mode WebView. Footer caché par défaut,
      // réapparaît au scroll vers le haut (via _onScrollDelta).
      _scrollStopTimer?.cancel();
      _inactivityTimer?.cancel();
      _animateHeaderTo(0.0);
      _animateFooterTo(1.0);
    }
  }

  void _onVideoPlayStateChanged(bool isPlaying) {
    if (!isPlaying) {
      _headerOffset.value = 0.0;
      _scrollStopTimer?.cancel();
    }
  }

  /// Smoothly animate the header to [target] offset (0.0 = visible, 1.0 = hidden).
  void _animateHeaderTo(double target) {
    _headerAutoController.stop();
    _headerAutoStart = _headerOffset.value;
    _headerAutoTarget = target;
    _headerAutoController.forward(from: 0);
  }

  /// Smoothly animate the footer to [target] offset (0.0 = visible, 1.0 = hidden).
  void _animateFooterTo(double target) {
    _footerAutoController.stop();
    _footerAutoStart = _footerOffset.value;
    _footerAutoTarget = target;
    _footerAutoController.forward(from: 0);
  }

  /// Apply a page-scroll-equivalent [delta] (positive = page going down)
  /// directly to the chrome offsets. Shared by the in-app scroll path and
  /// the WebView gesture path.
  void _applyChromeOffsetDelta(double delta) {
    final headerHeight =
        MediaQuery.of(context).padding.top + _kHeaderContentHeight;
    _headerOffset.value =
        (_headerOffset.value + delta / headerHeight).clamp(0.0, 1.0);

    if (!_footerPermanent.value) {
      final footerHeight = _kFooterContentHeight +
          MediaQuery.of(context).viewPadding.bottom;
      _footerOffset.value =
          (_footerOffset.value + delta / footerHeight).clamp(0.0, 1.0);
    }
  }

  /// Update header/footer offsets based on a native scroll delta (in-app
  /// reader only). Positive delta = scrolling down, negative = scrolling up.
  void _onScrollDelta(double delta) {
    if (delta == 0) return;
    if (_isWebViewActive) return;
    if (_showSunflowerNudge) {
      setState(() => _showSunflowerNudge = false);
    }
    final isVideo = _content?.isVideo ?? false;
    if (!isVideo && !_isShortArticle) {
      _applyChromeOffsetDelta(delta);
    }
    _scrollStopTimer?.cancel();
    _scrollStopTimer = Timer(const Duration(milliseconds: 2000), () {
      if (mounted) _animateFooterTo(0.0);
    });
    _inactivityTimer?.cancel();
    if (!isVideo && !_isShortArticle) {
      _inactivityTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && _headerOffset.value < 1.0) {
          _animateHeaderTo(1.0);
        }
      });
    }
  }

  /// Stop any in-flight reveal/hide tween so the live gesture pilots the
  /// chrome without fighting a residual animation.
  void _onGestureStart() {
    _headerAutoController.stop();
    _footerAutoController.stop();
  }

  /// Map a gesture-derived page-scroll-equivalent delta directly onto the
  /// chrome offsets. The signal is the user's finger, not `window.scrollY`,
  /// so no direction filter or hysteresis is needed.
  void _onGestureDelta(double pageDelta) {
    if (pageDelta == 0) return;
    if (_showSunflowerNudge) {
      setState(() => _showSunflowerNudge = false);
    }
    if (_content?.isVideo ?? false) return;
    _applyChromeOffsetDelta(pageDelta);
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _webScrollY > 0 && _headerOffset.value < 1.0) {
        _animateHeaderTo(1.0);
      }
    });
  }

  /// At touchend, commit the chrome to a clean state.
  /// - High-velocity flick → snap to that direction's endpoint.
  /// - Slow lift-off → leave the chrome at its current partial offset.
  /// - At the top of the page → force visible (overscroll guard).
  void _onGestureEnd(double velocityPxPerSec) {
    if (_content?.isVideo ?? false) return;
    // Forced overscroll-at-top behaviour: snap the chrome back to visible.
    if (_webScrollY <= 0) {
      if (_headerOffset.value != 0) _animateHeaderTo(0);
      if (!_footerPermanent.value && _footerOffset.value != 0) {
        _animateFooterTo(0);
      }
      return;
    }
    const double kVelocitySnapThreshold = 600.0; // px/s
    double? targetH;
    if (velocityPxPerSec > kVelocitySnapThreshold) {
      targetH = 1.0; // strong page-down flick → hide
    } else if (velocityPxPerSec < -kVelocitySnapThreshold) {
      targetH = 0.0; // strong page-up flick → show
    }
    if (targetH != null) {
      if (_headerOffset.value != targetH) _animateHeaderTo(targetH);
      if (!_footerPermanent.value && _footerOffset.value != targetH) {
        _animateFooterTo(targetH);
      }
    }
  }

  /// Returns whichever of [a] or [b] has the longest plain-text content.
  /// Falls back to the non-null value if one is empty/null.
  static String? _pickLongest(String? a, String? b) {
    final aLen = plainTextLength(a);
    final bLen = plainTextLength(b);
    if (aLen >= bLen && aLen > 0) return a;
    if (bLen > 0) return b;
    return a ?? b;
  }

  Future<void> _fetchContent() async {
    try {
      final supabase = Supabase.instance.client;
      final apiClient = ApiClient(supabase);
      final repository = FeedRepository(apiClient);
      final content = await repository.getContent(widget.contentId);

      if (mounted) {
        if (content != null) {
          // Merge: keep the longest text between initial content and API response.
          // Fixes cases where RSS provides longer htmlContent than the API
          // (e.g. Le Monde articles where enrichment returns a shorter version).
          final merged = content.copyWith(
            description:
                _pickLongest(content.description, _content?.description),
            htmlContent:
                _pickLongest(content.htmlContent, _content?.htmlContent),
            editorialBadge: content.editorialBadge ?? _content?.editorialBadge,
          );
          setState(() {
            _content = merged;
            _contentResolved = true;
            _isConsumed = _content!.status == ContentStatus.consumed;
          });
          final isVideoFetched = _content!.isVideo;
          if ((_content!.hasInAppContent == true || isVideoFetched) &&
              !_isConsumed) {
            _startReadingTimer();
          }
          // Re-check short article + measure article extent after content
          // loads and renders. We measure the extent on the next frame, but
          // the short-article check is delayed: `flutter_html` may need
          // multiple frames to finish laying out a long article, and an
          // eager check would mistakenly latch `_isShortArticle = true`.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _measureArticleExtent();
            }
          });
          Future.delayed(const Duration(milliseconds: 600), () {
            if (mounted) {
              _checkShortArticle();
            }
          });
          // Pre-load WebView if not already initialized
          if (_webViewController == null) {
            _initScrollToSiteWebView();
          }
          // Auto-fetch perspectives if not yet loaded
          if (_perspectivesResponse == null &&
              !_perspectivesLoading &&
              _content!.contentType == ContentType.article) {
            _fetchPerspectives();
          }
        } else {
          // Show error and pop if content not found
          setState(() => _contentResolved = true);
          NotificationService.showError('Contenu introuvable',
              context: context);
          context.pop();
        }
      }
    } catch (e) {
      debugPrint('Error fetching content: $e');
      if (mounted) {
        setState(() => _contentResolved = true);
        NotificationService.showError('Erreur de chargement', context: context);
        context.pop();
      }
    }
  }

  void _startReadingTimer() {
    _readingTimer?.cancel();
    _readingTimer = Timer(const Duration(seconds: _consumptionThreshold), () {
      if (mounted && !_isConsumed) {
        _markAsConsumed();
      }
    });
  }

  Future<void> _markAsConsumed() async {
    setState(() => _isConsumed = true);
    final content = _content;
    if (content == null) return;

    try {
      final supabase = Supabase.instance.client;
      final apiClient = ApiClient(supabase);
      final repository = FeedRepository(apiClient);
      await repository.updateContentStatus(
        content.id,
        ContentStatus.consumed,
      );

      // Silent update - no notification needed as this is tracked automatically
    } catch (e) {
      debugPrint('Error marking as consumed: $e');
    }
  }

  Future<void> _toggleBookmark() async {
    final content = _content;
    if (content == null) return;

    HapticFeedback.lightImpact();
    final wasSaved = content.isSaved;
    final newSaved = !wasSaved;
    setState(() {
      _content = content.copyWith(isSaved: newSaved);
    });

    try {
      final supabase = Supabase.instance.client;
      final apiClient = ApiClient(supabase);
      final repository = FeedRepository(apiClient);
      await repository.toggleSave(content.id, newSaved);
      if (mounted && newSaved) {
        // Auto-add to default collection
        final defaultCol = ref.read(defaultCollectionProvider);
        if (defaultCol != null) {
          final colRepo = ref.read(collectionsRepositoryProvider);
          await colRepo.addToCollection(defaultCol.id, content.id);
          ref.invalidate(collectionsProvider);
        }
        CollectionPickerSheet.show(
          context,
          content.id,
          onAddNote: () => _openNoteSheet(),
        );
      }
    } catch (e) {
      // Rollback on error
      if (mounted) {
        setState(() {
          _content = content.copyWith(isSaved: wasSaved);
        });
        NotificationService.showError('Erreur', context: context);
      }
    }
  }

  Future<void> _toggleLike() async {
    final content = _content;
    if (content == null) return;

    HapticFeedback.lightImpact();
    final wasLiked = content.isLiked;
    final newLiked = !wasLiked;
    // Cancel the pending nudge timer if the user sunflowers manually during
    // the 30s wait — avoids firing a redundant "Recommander ?" pill.
    _sunflowerNudgeTimer?.cancel();
    setState(() {
      _content = content.copyWith(isLiked: newLiked);
      _showSunflowerNudge = false;
    });

    // Bounce animation
    _likeBounceController.forward(from: 0);

    try {
      final supabase = Supabase.instance.client;
      final apiClient = ApiClient(supabase);
      final repository = FeedRepository(apiClient);
      await repository.toggleLike(content.id, newLiked);
      if (mounted) {
        NotificationService.showInfo(
          newLiked
              ? 'Ajouté à Mes contenus recommandés 🌻'
              : 'Retiré de Mes contenus recommandés 🌻',
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 94),
        );
        // Refresh collections to update liked collection counts
        ref.invalidate(collectionsProvider);
      }
    } catch (e) {
      // Rollback on error
      if (mounted) {
        setState(() {
          _content = content.copyWith(isLiked: wasLiked);
        });
        NotificationService.showError('Erreur', context: context);
      }
    }
  }

  Future<void> _shareArticle() async {
    final content = _content;
    if (content == null) return;

    await Clipboard.setData(ClipboardData(text: content.url));
    if (mounted) {
      setState(() => _linkCopiedHeader = true);
      _linkCopiedHeaderTimer?.cancel();
      _linkCopiedHeaderTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _linkCopiedHeader = false);
      });
    }
  }

  Widget _buildLinkCopiedTooltip(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.inverseSurface,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
            size: 14,
            color: colorScheme.onInverseSurface,
          ),
          const SizedBox(width: 4),
          Text(
            'Lien copié !',
            style: TextStyle(
              color: colorScheme.onInverseSurface,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openNoteSheet() async {
    final content = _content;
    if (content == null) return;

    // Capture state before opening sheet
    final wasAlreadySaved = content.isSaved;
    final hadNote = content.hasNote;

    _hasOpenedNote = true;
    await NoteInputSheet.show(
      context,
      contentId: content.id,
      initialNoteText: content.noteText,
      onFirstCharacter: () {
        // Auto-bookmark (visual feedback deferred to sheet close)
        if (!content.isSaved) {
          setState(() {
            _content = content.copyWith(isSaved: true);
          });
        }
      },
      onNoteSaved: (text) {
        if (mounted) {
          setState(() {
            _content = _content?.copyWith(
              noteText: text,
              noteUpdatedAt: DateTime.now(),
              isSaved: true,
            );
          });
        }
      },
      onNoteDeleted: () {
        if (mounted) {
          setState(() {
            _content = _content?.clearNote();
          });
        }
      },
    );

    // Sheet closed — visual feedback if a note was created
    if (mounted && _content != null && _content!.hasNote && !hadNote) {
      _bookmarkBounceController.forward(from: 0);
      if (!wasAlreadySaved) {
        NotificationService.showInfo(
          'Sauvegardé',
          actionLabel: 'Ajouter à une collection',
          onAction: () => CollectionPickerSheet.show(context, _content!.id),
        );
      }
    }
  }

  void _maybeTriggerPerspectivesCta() {
    if (_perspectivesCtaTriggered) return;
    final response = _perspectivesResponse;
    if (response == null) return;
    if (response.perspectives.isEmpty || !response.shouldDisplay) return;
    _perspectivesCtaTriggered = true;
    NudgeCounters.increment(NudgeCounters.articleWithPerspectivesCount)
        .then((count) async {
      if (!mounted) return;
      if (count < 2) return;
      final coordinator = ref.read(nudgeCoordinatorProvider);
      final active = await coordinator.request(NudgeIds.perspectivesCta);
      if (!mounted) return;
      if (active != NudgeIds.perspectivesCta) return;
      _playPerspectivesPulse();
    });
  }

  void _playPerspectivesPulse() {
    _perspectivesPulseController ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _perspectivesPulseScale ??= TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.08), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.08, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(
      parent: _perspectivesPulseController!,
      curve: Curves.easeOutCubic,
    ));
    _perspectivesPulseController!.forward(from: 0).whenComplete(() async {
      if (!mounted) return;
      final coordinator = ref.read(nudgeCoordinatorProvider);
      if (coordinator.activeId == NudgeIds.perspectivesCta) {
        await coordinator.dismiss(markSeen: true);
      }
    });
    setState(() {});
  }

  @override
  void dispose() {
    // Capture max progress reached before disposing ValueNotifier
    final progressPct = (_maxReadingProgress * 100).round().clamp(0, 100);

    // Persist reading progress + analytics on close.
    // Must happen before super.dispose() — ref.read() requires active ConsumerState.
    try {
      if (_content != null) {
        final duration = DateTime.now().difference(_startTime).inSeconds;

        final supabase = Supabase.instance.client;
        final apiClient = ApiClient(supabase);
        final repository = FeedRepository(apiClient);

        // Persist reading progress via status endpoint
        if (progressPct > 0) {
          repository.updateContentStatusWithProgress(
            _content!.id,
            progressPct,
          );
        }

        // Accumulate reading time on user_content_status for recommendation signal.
        repository.updateContentStatusWithTimeSpent(
          _content!.id,
          duration,
        );

        // Track article read duration
        ref.read(analyticsServiceProvider).trackArticleRead(
              _content!.id,
              _content!.source.id,
              duration,
            );
      }
    } catch (e) {
      debugPrint('Error tracking on dispose: $e');
    }

    _readingTimer?.cancel();
    _noteNudgeTimer?.cancel();
    _scrollStopTimer?.cancel();
    _sunflowerNudgeTimer?.cancel();
    _inactivityTimer?.cancel();
    _articleLayerUnmountTimer?.cancel();
    _linkCopiedHeaderTimer?.cancel();
    _bookmarkBounceController.dispose();
    _likeBounceController.dispose();
    _perspectivesPulseController?.dispose();
    _exitAnimController.dispose();
    _headerAutoController.dispose();
    _footerAutoController.dispose();
    _ctaPulseController.dispose();
    _footerPermanent.removeListener(_onFooterPermanentChanged);
    WidgetsBinding.instance.removeObserver(this);
    _headerOffset.dispose();
    _footerOffset.dispose();
    _footerPermanent.dispose();
    _readingProgress.removeListener(_onReadingProgressNudge);
    _readingProgress.dispose();
    _scrollController.removeListener(_onScrollToSite);
    _scrollController.removeListener(_onScrollReadingProgress);

    _scrollController.dispose();
    _inAppScrollController.dispose();
    super.dispose();
  }

  /// Handle video progress updates from YouTubePlayerWidget.
  void _onVideoProgressChanged(double progress) {
    final progressPct = (progress * 100).round().clamp(0, 100);
    final currentPct = (_readingProgress.value * 100).round();

    // Update the reading progress notifier
    _readingProgress.value = progress;
    if (progress > _maxReadingProgress) {
      _maxReadingProgress = progress;
    }

    // Persist at thresholds: 25%, 50%, 75%, 100%
    const thresholds = [25, 50, 75, 100];
    for (final threshold in thresholds) {
      if (progressPct >= threshold && currentPct < threshold) {
        _persistVideoProgress(progressPct);
        break;
      }
    }
  }

  /// Persist video watch progress to the backend.
  Future<void> _persistVideoProgress(int progressPct) async {
    final content = _content;
    if (content == null) return;
    try {
      final supabase = Supabase.instance.client;
      final apiClient = ApiClient(supabase);
      final repository = FeedRepository(apiClient);
      await repository.updateContentStatusWithProgress(content.id, progressPct);
    } catch (e) {
      debugPrint('Error persisting video progress: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isExitAnimating) {
      _exitAnimController.reset();
      setState(() {
        _isExitAnimating = false;
      });
    }
  }

  Future<void> _animateAndLaunch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (!await canLaunchUrl(uri)) return;
    if (reduceMotion) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }

    setState(() => _isExitAnimating = true);
    await _exitAnimController.forward(from: 0.0);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openOriginalUrl() async {
    final url = _content?.url;
    if (url != null) {
      await _animateAndLaunch(url);
    }
  }

  String _getFabLabel() {
    switch (_content?.contentType) {
      case ContentType.youtube:
        return 'Ouvrir sur YouTube';
      case ContentType.audio:
        return 'Voir la source';
      default:
        return 'Voir l\'original';
    }
  }

  /// Pre-fetch perspectives for the pill widget
  Future<void> _fetchPerspectives() async {
    final content = _content;
    if (content == null) return;

    setState(() => _perspectivesLoading = true);

    try {
      final repository = ref.read(feedRepositoryProvider);

      final response = await repository.getPerspectives(content.id);

      if (mounted) {
        setState(() {
          _perspectivesResponse = response;
          _perspectivesLoading = false;
          if (response.perspectives.isEmpty) _perspectivesExpanded = false;
        });
        _maybeTriggerPerspectivesCta();
      }
    } catch (e) {
      debugPrint('Error pre-fetching perspectives: $e');
      if (mounted) {
        setState(() => _perspectivesLoading = false);
      }
    }
  }

  /// Request Facteur analysis for the perspectives section.
  /// Called by the floating button in the article reader.
  Future<void> _requestPerspectivesAnalysis() async {
    final contentId = _perspectivesResponse?.perspectives.isNotEmpty == true
        ? _content?.id
        : null;
    if (contentId == null) return;

    setState(
        () => _perspectivesAnalysisState = PerspectivesAnalysisState.loading);

    // Scroll to analysis zone so the user can see the progress
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _analysisZoneKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
          alignment: 0.8,
        );
      }
    });

    try {
      final repository = ref.read(feedRepositoryProvider);
      final result = await repository.analyzePerspectives(contentId);
      if (!mounted) return;
      setState(() {
        _perspectivesAnalysisText = result;
        _perspectivesAnalysisState = result != null
            ? PerspectivesAnalysisState.done
            : PerspectivesAnalysisState.error;
      });
    } catch (e) {
      debugPrint('Error requesting perspectives analysis: $e');
      if (!mounted) return;
      setState(
          () => _perspectivesAnalysisState = PerspectivesAnalysisState.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    final content = _content;

    // If no content passed, show loading or error
    if (content == null) {
      return Scaffold(
        backgroundColor: colors.backgroundPrimary,
        appBar: AppBar(
          backgroundColor: colors.backgroundPrimary,
          leading: IconButton(
            icon: Icon(
              PhosphorIcons.arrowLeft(PhosphorIconsStyle.regular),
              color: colors.textPrimary,
            ),
            onPressed: () => context.pop(),
          ),
        ),
        body: Center(
          child: CircularProgressIndicator(color: colors.primary),
        ),
      );
    }

    // Premium source → redirect to external browser for authenticated access
    final userSources = ref.read(userSourcesProvider).valueOrNull ?? [];
    final isPremiumSource =
        userSources.any((s) => s.id == content.source.id && s.hasSubscription);
    if (isPremiumSource &&
        content.url.isNotEmpty &&
        !_premiumRedirectScheduled) {
      _premiumRedirectScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final uri = Uri.tryParse(content.url);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        if (mounted) context.pop();
      });
      return Scaffold(
        backgroundColor: colors.backgroundPrimary,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: colors.primary),
              const SizedBox(height: FacteurSpacing.space4),
              Text(
                'Ouverture dans votre navigateur...',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    // Determine display mode:
    // - Articles with in-app content: progressive scroll-to-site
    // - Non-articles or explicit WebView toggle: old behavior
    // Skip scroll-to-site for articles with too little content
    final articleText = content.htmlContent ?? content.description;
    final hasEnoughContent = plainTextLength(articleText) >= 100;
    final useScrollToSite = content.hasInAppContent &&
        content.contentType == ContentType.article &&
        hasEnoughContent &&
        !_showWebView &&
        !kIsWeb;
    final useInAppReading =
        content.hasInAppContent && !_showWebView && !useScrollToSite;
    final isVideoContent = content.isVideo;

    // Web: no WebView available — auto-redirect to original URL
    if (kIsWeb &&
        !useScrollToSite &&
        !useInAppReading &&
        !isVideoContent &&
        content.url.isNotEmpty &&
        !_webFallbackRedirectScheduled) {
      _webFallbackRedirectScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final uri = Uri.tryParse(content.url);
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
        if (mounted) context.pop();
      });
      return Scaffold(
        backgroundColor: colors.backgroundPrimary,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: colors.primary),
              const SizedBox(height: FacteurSpacing.space4),
              Text(
                'Ouverture dans votre navigateur...',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      body: AnimatedBuilder(
        animation: _exitAnimController,
        builder: (context, child) {
          final scale = 1.0 - 0.03 * _exitAnimController.value;
          return Transform.scale(
            scale: _isExitAnimating ? scale : 1.0,
            child: child,
          );
        },
        child: Stack(
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollUpdateNotification) {
                  final delta = notification.scrollDelta ?? 0.0;
                  final metrics = notification.metrics;
                  if (metrics.pixels <= 0 && !_isWebViewActive) {
                    _headerOffset.value = 0.0;
                    _footerOffset.value = 0.0;
                  }

                  _onScrollDelta(delta);
                  // Track reading progress from any scrollable (including in-app reader)
                  if (metrics.maxScrollExtent > 0) {
                    final rawProgress =
                        metrics.pixels / metrics.maxScrollExtent;
                    // Footer becomes permanent at end of ALL content (incl.
                    // perspectives) for native in-app reading. Skip for
                    // scroll-to-site (CTA tapped) where reaching the end means
                    // revealing the WebView, not finishing reading — locking
                    // the footer there would freeze it visible during the
                    // entire WebView session.
                    if (!_footerPermanent.value &&
                        !_ctaTapped &&
                        rawProgress >= 0.98) {
                      _footerPermanent.value = true;
                      _animateFooterTo(0.0);
                    }
                    // Progress bar uses article-only extent so perspectives don't dilute it
                    final articleExtent =
                        _articleContentExtent ?? metrics.maxScrollExtent;
                    final barProgress = metrics.pixels / articleExtent;
                    final capped = _isPartialContent
                        ? (barProgress * 0.25).clamp(0.0, 0.25)
                        : barProgress.clamp(0.0, 1.0);
                    _readingProgress.value = capped;
                    if (capped > _maxReadingProgress) {
                      _maxReadingProgress = capped;
                    }
                  }
                }
                return false;
              },
              child: Positioned.fill(
                child: isVideoContent
                    ? _buildVideoContent(context, content)
                    : useScrollToSite
                        ? _buildScrollToSiteContent(context, content)
                        : useInAppReading
                            ? _buildInAppContent(context, content)
                            : _buildWebViewFallback(content),
              ),
            ),
            // Header — follows scroll: slides up on scroll-down, back on scroll-up
            // For short articles the header stays pinned (offset is never updated).
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: ValueListenableBuilder<double>(
                valueListenable: _headerOffset,
                builder: (context, offset, child) {
                  final headerHeight = MediaQuery.of(context).padding.top +
                      _kHeaderContentHeight;
                  return Transform.translate(
                    offset: Offset(0, -offset * headerHeight),
                    child: child!,
                  );
                },
                // RepaintBoundary isolates the header's render layer so the
                // per-pixel Transform.translate driven by _headerOffset only
                // recomposites this layer — the article body underneath is
                // not invalidated.
                child: RepaintBoundary(child: _buildHeader(context, content)),
              ),
            ),
            // Reading progress bar — follows header position continuously
            if (content.hasInAppContent ||
                _isWebViewActive ||
                isVideoContent ||
                (!useScrollToSite && !useInAppReading))
              ValueListenableBuilder<double>(
                valueListenable: _headerOffset,
                builder: (context, offset, _) {
                  final statusBarHeight = MediaQuery.of(context).padding.top;
                  final topWhenHeaderVisible =
                      statusBarHeight + _kHeaderVisualBottom;
                  final topWhenHeaderHidden = statusBarHeight;
                  final top = topWhenHeaderVisible -
                      offset * (topWhenHeaderVisible - topWhenHeaderHidden);
                  return Positioned(
                    top: top,
                    left: 0,
                    right: 0,
                    child: RepaintBoundary(
                      child: _buildReadingProgressBar(colors),
                    ),
                  );
                },
              ),
            // Exit animation overlay — fade-to-white + scale-down
            if (_isExitAnimating)
              AnimatedBuilder(
                animation: _exitAnimController,
                builder: (context, _) {
                  return Positioned.fill(
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: Colors.white
                            .withValues(alpha: 0.6 * _exitAnimController.value),
                      ),
                    ),
                  );
                },
              ),
            // Floating "Lancer l'analyse Facteur" button — in-app articles only.
            // Visible when the perspectives section is expanded and analysis
            // hasn't been triggered yet.
            if (useInAppReading && content.contentType == ContentType.article)
              Builder(
                builder: (context) {
                  final show = _perspectivesExpanded &&
                      _perspectivesAnalysisState ==
                          PerspectivesAnalysisState.idle &&
                      _perspectivesResponse != null &&
                      _perspectivesResponse!.perspectives.isNotEmpty;
                  return Positioned(
                    right: 16,
                    bottom: _kFooterContentHeight +
                        MediaQuery.of(context).viewPadding.bottom +
                        12,
                    child: AnimatedScale(
                      scale: show ? 1.0 : 0.9,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      child: AnimatedOpacity(
                        opacity: show ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: IgnorePointer(
                          ignoring: !show,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: context.facteurColors.surfaceElevated
                                  .withValues(alpha: 0.95),
                              border: Border.all(
                                color: context.facteurColors.border,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: OutlinedButton.icon(
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                _requestPerspectivesAnalysis();
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: context.facteurColors.primary,
                                side: BorderSide.none,
                                backgroundColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: Icon(
                                PhosphorIcons.sparkle(PhosphorIconsStyle.fill),
                                size: 16,
                              ),
                              label: const Text('Lancer l\'analyse Facteur'),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            // Footer — always rendered, mirrors header slide behavior.
            // Article: full layout. Video/audio: external CTA + bookmark + sunflower.
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildContentFooter(
                context,
                content,
                isPureWebview:
                    _showWebView && !useScrollToSite && !useInAppReading,
              ),
            ),
          ],
        ),
      ),
      // All actions migrated to the persistent footer (article + video/audio).
      floatingActionButton: null,
    );
  }

  /// CTA handler for "Lire sur…" in the footer.
  /// For scroll-to-site mode: reveals WebView via scroll animation on first tap,
  /// then opens external link on subsequent taps.
  /// For all other modes: opens external link directly.
  void _onReadOnSiteTap() {
    if (kIsWeb) {
      _openOriginalUrl();
      return;
    }
    final content = _content;
    if (content == null) return;
    final articleText = content.htmlContent ?? content.description;
    final hasEnoughContent = plainTextLength(articleText) >= 100;
    final isScrollToSite = content.hasInAppContent &&
        content.contentType == ContentType.article &&
        hasEnoughContent &&
        !_showWebView;
    if (isScrollToSite && !_ctaTapped) {
      setState(() => _ctaTapped = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOutCubic,
          );
        }
      });
      return;
    }

    // Already in any WebView mode (scroll-to-site revealed, fallback active,
    // or the user has explicitly tapped the CTA once): the next tap is the
    // user opting in to the external browser.
    if (_isWebViewActive || _showWebView || _ctaTapped) {
      _openOriginalUrl();
      return;
    }

    // First CTA tap on an article that did NOT qualify for scroll-to-site
    // (htmlContent missing or too short — common race on Android). Reveal
    // the internal WebView instead of jumping straight to the external
    // browser, so the user stays inside the reader.
    unawaited(Sentry.addBreadcrumb(Breadcrumb(
      category: 'reader.cta',
      message: 'fallback to internal webview',
      level: SentryLevel.info,
      data: {
        'contentId': content.id,
        'contentType': content.contentType.name,
        'hasInAppContent': content.hasInAppContent,
        'plainTextLen': plainTextLength(articleText),
        'platform': defaultTargetPlatform.name,
      },
    )));
    setState(() {
      _showWebView = true;
      _ctaTapped = true;
    });
  }

  /// External-source CTA used in the footer for video/audio readers.
  /// Mirrors the article footer's "Lire via Navigateur" outlined style but
  /// without the permanent-orange logic.
  Widget _buildExternalCtaButton(BuildContext context, Content content) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final showLogo = content.source.logoUrl != null;
    return OutlinedButton(
      onPressed: _openOriginalUrl,
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.5),
        foregroundColor: colors.textPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        side: BorderSide(color: colors.border.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      child: Row(
        children: [
          if (showLogo) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: content.source.logoUrl!,
                width: 28,
                height: 28,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              _getFabLabel(),
              style: textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.left,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            PhosphorIcons.arrowUpRight(PhosphorIconsStyle.regular),
            size: 16,
            color: colors.textSecondary,
          ),
        ],
      ),
    );
  }

  /// Persistent footer bar shown for all reader types.
  /// Mirrors header slide behavior: hides on scroll-down, shows on scroll-up.
  /// Article: full layout (CTA + Perspectives + Sauvegarder + Recommander).
  /// Video/audio: simplified (CTA externe + Sauvegarder + Recommander).
  Widget _buildContentFooter(
    BuildContext context,
    Content content, {
    bool isPureWebview = false,
  }) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    // Pour la webview pure (article sans in-app content), la section
    // perspectives n'est jamais rendue → masquer le bouton perspectives qui
    // n'aurait aucun effet.
    final isArticle =
        content.contentType == ContentType.article && !isPureWebview;

    const iconButtonStyle = ButtonStyle(
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      padding: WidgetStatePropertyAll(EdgeInsets.all(10)),
      minimumSize: WidgetStatePropertyAll(Size(52, 52)),
      shape: WidgetStatePropertyAll(CircleBorder()),
    );

    final footerContent = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.backgroundPrimary,
        border: Border(
          top: BorderSide(
              color: colors.border.withValues(alpha: 0.5), width: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // CTA — sized to content for articles (laisse de la place aux 3
              // boutons icônes à droite); fills width pour video/audio.
              // Article: dynamic "Article complet" / "Lire via Navigateur"
              // with permanent-orange logic. Video/audio: simple external CTA.
              Flexible(
                fit: FlexFit.loose,
                child: SizedBox(
                  height: 53,
                  child: isArticle
                      ? ValueListenableBuilder<bool>(
                    valueListenable: _footerPermanent,
                    builder: (context, permanent, _) {
                      final isWebViewMode = _ctaTapped || _isWebViewActive;
                      // Primary orange ONLY when the user has reached the
                      // bottom of the article (footer locked permanent) AND
                      // the WebView hasn't been revealed yet.
                      final usePrimary = permanent && !isWebViewMode;

                      final label = isWebViewMode
                          ? 'Lire via Navigateur'
                          : 'Article complet';
                      final showLogo = !isWebViewMode;
                      final iconData = isWebViewMode
                          ? PhosphorIcons.arrowUpRight(
                              PhosphorIconsStyle.regular)
                          : PhosphorIcons.arrowDown(
                              PhosphorIconsStyle.regular);

                      final children = <Widget>[
                        if (showLogo) ...[
                          SourceLogoAvatar(
                            source: content.source,
                            size: 28,
                            radius: 8,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            label,
                            style: textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: usePrimary
                                  ? Colors.white
                                  : colors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.left,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          iconData,
                          size: 16,
                          color: usePrimary
                              ? Colors.white.withValues(alpha: 0.8)
                              : colors.textSecondary,
                        ),
                      ];

                      if (usePrimary) {
                        return AnimatedBuilder(
                          animation: _ctaPulseController,
                          builder: (context, child) {
                            // Subtle pop: 1.0 → 1.04 → 1.0 over 280ms.
                            final t = _ctaPulseController.value;
                            final scale = 1.0 + 0.04 * math.sin(t * math.pi);
                            return Transform.scale(scale: scale, child: child);
                          },
                          child: FilledButton(
                            onPressed: _onReadOnSiteTap,
                            style: FilledButton.styleFrom(
                              backgroundColor: colors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: children,
                            ),
                          ),
                        );
                      }

                      return OutlinedButton(
                        onPressed: _onReadOnSiteTap,
                        style: OutlinedButton.styleFrom(
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.5),
                          foregroundColor: colors.textPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          side: BorderSide(
                              color: colors.border.withValues(alpha: 0.5)),
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        child: Row(children: children),
                      );
                    },
                  )
                      : _buildExternalCtaButton(context, content),
                ),
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
              // Sauvegarder (long-press → collection picker)
              GestureDetector(
                onLongPress: () {
                  HapticFeedback.mediumImpact();
                  CollectionPickerSheet.show(
                    context,
                    content.id,
                    onAddNote: () => _openNoteSheet(),
                  );
                },
                child: ScaleTransition(
                  scale: _bookmarkScaleAnimation,
                  child: IconButton(
                    style: iconButtonStyle.copyWith(
                      backgroundColor: content.isSaved
                          ? WidgetStatePropertyAll(colors.primary)
                          : null,
                    ),
                    onPressed: _toggleBookmark,
                    icon: Icon(
                      content.isSaved
                          ? PhosphorIcons.bookmarkSimple(
                              PhosphorIconsStyle.fill)
                          : PhosphorIcons.bookmarkSimple(
                              PhosphorIconsStyle.regular),
                      size: 28,
                      color:
                          content.isSaved ? Colors.white : colors.textSecondary,
                    ),
                    tooltip: 'Sauvegarder',
                  ),
                ),
              ),

              // 🌻 Recommander
              ScaleTransition(
                scale: _likeScaleAnimation,
                child: IconButton(
                  style: iconButtonStyle.copyWith(
                    backgroundColor: content.isLiked
                        ? WidgetStatePropertyAll(colors.primary)
                        : null,
                  ),
                  onPressed: _toggleLike,
                  icon: SunflowerIcon(
                    isActive: content.isLiked,
                    size: 26,
                    inactiveColor: colors.textSecondary,
                  ),
                  tooltip: 'Recommander',
                ),
              ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return ValueListenableBuilder<double>(
      valueListenable: _footerOffset,
      builder: (context, offset, child) => Transform.translate(
        // Extra 8px to slide the top border shadow fully off-screen.
        offset: Offset(0, offset * (_kFooterContentHeight + bottomInset + 8)),
        // RepaintBoundary isolates the footer subtree from per-pixel
        // _footerOffset updates — the translation only recomposites this
        // layer, the article body is not invalidated.
        child: RepaintBoundary(child: child),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 16, bottom: 8),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.3),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: _showSunflowerNudge
                  ? Container(
                      key: const ValueKey('nudge_visible'),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF8E1).withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Text(
                        'Recommander ? 🌻',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF795548),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(
                      key: ValueKey('nudge_hidden'),
                    ),
            ),
          ),
          footerContent,
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Content content) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    // Live follow state — relies on the unified 4-state interests provider
    // so the chip reflects an optimistic toggle from anywhere in the app
    // (and disappears the instant the user taps "+ Suivre" below).
    final sourcesState = ref.watch(userSourcesStateProvider).valueOrNull;
    final liveState = sourcesState?.stateOf(content.source.id);
    final isFollowedLive = liveState == InterestState.followed ||
        liveState == InterestState.favorite ||
        // Fallback to the article payload before the provider has loaded —
        // avoids a flash of the chip on cold open.
        (liveState == null && content.isFollowedSource);

    // ColoredBox fills the status bar area; SafeArea pushes content below it
    final headerContent = ColoredBox(
      color: colors.backgroundPrimary,
      child: SafeArea(
        bottom: false,
        child: Container(
          padding: const EdgeInsets.only(
            top: FacteurSpacing.space4,
            bottom: FacteurSpacing.space2,
            left: FacteurSpacing.space2,
            right: FacteurSpacing.space2,
          ),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: FacteurSpacing.space2),
            child: Row(
              children: [
                // Discreet Back Button (reduced icon, maintained hitbox)
                IconButton(
                  padding: const EdgeInsets.all(8),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    PhosphorIcons.arrowLeft(PhosphorIconsStyle.regular),
                    size: 16,
                    color: colors.textSecondary,
                  ),
                  onPressed: _isWebViewActive
                      ? _exitWebViewMode
                      : () => context.pop(_content),
                ),
                const SizedBox(width: 4),

                // Source logo + name + gear: tappable → filter feed by source
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: _SourceBadgeNudge(
                          child: GestureDetector(
                            onTap: () {
                              ref
                                  .read(feedProvider.notifier)
                                  .setSource(content.source.id);
                              ref
                                  .read(feedScrollTriggerProvider.notifier)
                                  .state++;
                              context.pop(_content);
                            },
                            onLongPress: () => TopicChip.showArticleSheet(
                              context,
                              content,
                              initialSection: ArticleSheetSection.source,
                            ),
                            behavior: HitTestBehavior.opaque,
                            child: Row(
                              children: [
                                // Source logo (28px, fallback initiales)
                                SourceLogoAvatar(
                                  source: content.source,
                                  size: 28,
                                  radius: 10,
                                ),
                                const SizedBox(width: 8),

                                // Source Name + Time + Badges
                                Flexible(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Ligne 1 : Nom (mini-chip) + Badges
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Opacity(
                                              opacity: 0.9,
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Color.lerp(
                                                      colors
                                                          .backgroundSecondary,
                                                      Colors.black,
                                                      0.003)!,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  content.source.name,
                                                  style: textTheme.labelMedium
                                                      ?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                    color: colors.textPrimary,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                          ),
                                          // Bias dot
                                          if (content.source.biasStance !=
                                              'unknown') ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              width: 7,
                                              height: 7,
                                              decoration: BoxDecoration(
                                                color: content.source
                                                    .getBiasColor(),
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          ],
                                          // Editorial badge (digest articles)
                                          if (content.editorialBadge !=
                                              null) ...[
                                            const SizedBox(width: 6),
                                            EditorialBadge.chip(
                                                  content.editorialBadge,
                                                  context: context,
                                                ) ??
                                                const SizedBox.shrink(),
                                          ],
                                          // Gear icon — same scale as bias dot
                                          const SizedBox(width: 4),
                                          Material(
                                            color: Colors.transparent,
                                            shape: const CircleBorder(),
                                            clipBehavior: Clip.antiAlias,
                                            child: InkWell(
                                              onTap: () =>
                                                  TopicChip.showArticleSheet(
                                                context,
                                                content,
                                                initialSection:
                                                    ArticleSheetSection.source,
                                              ),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.all(3),
                                                child: Icon(
                                                  PhosphorIcons.gear(
                                                      PhosphorIconsStyle
                                                          .regular),
                                                  size: 11,
                                                  color: colors.textTertiary,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 1),
                                      // Ligne 2 : Temps relatif (icône + format court)
                                      Row(
                                        children: [
                                          Icon(
                                            PhosphorIcons.clock(
                                                PhosphorIconsStyle.regular),
                                            size: 11,
                                            color: colors.textTertiary,
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            timeago
                                                .format(content.publishedAt,
                                                    locale: 'fr_short')
                                                .replaceAll('il y a ', ''),
                                            style:
                                                textTheme.bodySmall?.copyWith(
                                              color: colors.textTertiary,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ), // _SourceBadgeNudge
                      ),
                      if (!isFollowedLive) ...[
                        const SizedBox(width: 8),
                        _FollowSourceChip(
                          sourceId: content.source.id,
                          colors: colors,
                        ),
                      ],
                    ],
                  ),
                ),

                // Share button — copie le lien dans le presse-papier
                IconButton(
                  padding: const EdgeInsets.all(8),
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(),
                  style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    minimumSize: const Size(38, 38),
                    shape: const CircleBorder(),
                  ),
                  onPressed: _shareArticle,
                  icon: Icon(
                    PhosphorIcons.shareNetwork(PhosphorIconsStyle.regular),
                    size: 22,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        headerContent,
        if (_linkCopiedHeader)
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 16, right: 16),
              child: _buildLinkCopiedTooltip(context),
            ),
          ),
      ],
    );
  }

  double _measureChipWidth(String text, TextStyle? style,
      {bool isEntity = false}) {
    const chipHPad = 16.0;
    const followIconExtra = 13.0; // icon 10px + gap 3px
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: isEntity ? 100.0 : double.infinity);
    return tp.width + chipHPad + (isEntity ? followIconExtra : 0);
  }

  /// Greedy Wrap simulation: returns how many items from [widths] fit within
  /// [maxLines] lines of [availWidth], using [spacing] between items.
  int _simulateWrapVisible(
    List<double> widths,
    double availWidth, {
    double spacing = 6.0,
    int maxLines = 2,
  }) {
    int line = 1;
    double x = 0;
    int count = 0;
    for (final w in widths) {
      final newX = x == 0 ? w : x + spacing + w;
      if (newX <= availWidth) {
        x = newX;
      } else {
        if (line >= maxLines) break;
        line++;
        x = w;
      }
      count++;
    }
    return count;
  }

  /// Builds a 2-line-max Wrap of article chips: Aperçu (if partial) + topic
  /// chips + entity chips, followed by a +X overflow chip if needed.
  Widget _buildTagsWrap(BuildContext context, Content content,
      {bool isPartial = false}) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final labelStyle = textTheme.labelSmall;
    final topicsAsync = ref.watch(customTopicsProvider);
    final followedNames = (topicsAsync.valueOrNull ?? [])
        .where((t) => t.canonicalName != null)
        .map((t) => t.canonicalName!.toLowerCase())
        .toSet();

    // Build ordered chip list: (widget, estimatedWidth)
    final chips = <({Widget widget, double width})>[];

    if (isPartial) {
      const label = 'Aperçu — contenu partiel';
      chips.add((
        widget: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: colors.warning.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: labelStyle?.copyWith(
              color: colors.warning,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        width: _measureChipWidth(label, labelStyle),
      ));
    }

    if (content.topics.isNotEmpty) {
      final macroTheme = getTopicMacroTheme(content.topics.first);
      if (macroTheme != null) {
        final emoji = getMacroThemeEmoji(macroTheme);
        final label = '${emoji.isNotEmpty ? '$emoji ' : ''}$macroTheme';
        chips.add((
          widget: GestureDetector(
            onTap: () => TopicChip.showArticleSheet(context, content,
                initialSection: ArticleSheetSection.topic),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colors.textTertiary.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                label,
                style: labelStyle?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          width: _measureChipWidth(label, labelStyle),
        ));
      }
      final topicLabel = getTopicLabel(content.topics.first);
      // Skip topic chip when its label duplicates the macro-theme name.
      if (topicLabel.toLowerCase() != macroTheme?.toLowerCase()) {
        chips.add((
          widget: GestureDetector(
            onTap: () => TopicChip.showArticleSheet(context, content,
                initialSection: ArticleSheetSection.topic),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colors.textTertiary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                topicLabel,
                style: labelStyle?.copyWith(
                  color: colors.textTertiary,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          width: _measureChipWidth(topicLabel, labelStyle),
        ));
      }
    }

    for (final entity in content.entities) {
      final isFollowed = followedNames.contains(entity.text.toLowerCase());
      chips.add((
        widget: GestureDetector(
          onTap: () => TopicChip.showArticleSheet(context, content,
              initialSection: ArticleSheetSection.entities),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isFollowed
                  ? const Color(0xFFE07A5F).withValues(alpha: 0.15)
                  : colors.textTertiary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 100),
                  child: Text(
                    entity.text,
                    style: labelStyle?.copyWith(
                      color: isFollowed
                          ? const Color(0xFFE07A5F)
                          : colors.textTertiary,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isFollowed) ...[
                  const SizedBox(width: 3),
                  Icon(
                    PhosphorIcons.check(PhosphorIconsStyle.bold),
                    size: 10,
                    color: const Color(0xFFE07A5F),
                  ),
                ],
              ],
            ),
          ),
        ),
        width: _measureChipWidth(entity.text, labelStyle, isEntity: true),
      ));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(builder: (context, constraints) {
      const spacing = 6.0;
      final availWidth = constraints.maxWidth;
      final widths = chips.map((c) => c.width).toList();

      // How many chips fit in 2 lines without any overflow chip?
      int visibleCount = _simulateWrapVisible(widths, availWidth);
      final total = chips.length;

      if (visibleCount < total) {
        // Need an overflow chip — find the largest visibleCount such that
        // [visibleCount chips + overflow chip] all fit within 2 lines.
        // Use the max possible overflow width for a stable estimate.
        final overflowChipW = _measureChipWidth('+$total', labelStyle);
        while (visibleCount > 0) {
          final test = [...widths.take(visibleCount), overflowChipW];
          if (_simulateWrapVisible(test, availWidth) == test.length) break;
          visibleCount--;
        }
      }

      final overflow = total - visibleCount;

      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          ...chips.take(visibleCount).map((c) => c.widget),
          if (overflow > 0)
            GestureDetector(
              onTap: () => TopicChip.showArticleSheet(context, content,
                  initialSection: ArticleSheetSection.entities),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.textTertiary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '+$overflow',
                  style: labelStyle?.copyWith(
                    color: colors.textTertiary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }

  Widget _buildReadingProgressBar(FacteurColors colors) {
    return ValueListenableBuilder<double>(
      valueListenable: _readingProgress,
      builder: (context, progress, _) {
        // Only show after 5% to avoid flashing on open
        if (progress < 0.05) return const SizedBox.shrink();
        final clamped = progress.clamp(0.0, 1.0);
        // Grey→primary color with progressive opacity (20%→100%)
        final alpha = 0.2 + (clamped * 0.8); // 20% at start → 100% at end
        final barColor = Color.lerp(
          Colors.grey.shade400,
          colors.primary,
          clamped,
        )!
            .withValues(alpha: alpha);
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(end: clamped),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          builder: (context, smoothProgress, _) => SizedBox(
            height: 6.5,
            child: LinearProgressIndicator(
              value: smoothProgress,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
              minHeight: 6.5,
            ),
          ),
        );
      },
    );
  }

  /// Inline "Article complet" button shown at the end of the body when the
  /// article is in partial mode — replaces the dismissible nudge for partial
  /// articles since reading-on-site is the only path to the full content.
  Widget _buildPartialArticleInlineButton(BuildContext context, Content content) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FacteurSpacing.space4,
        vertical: FacteurSpacing.space4,
      ),
      child: SizedBox(
        height: 53,
        child: OutlinedButton(
          onPressed: _onReadOnSiteTap,
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.5),
            foregroundColor: colors.textPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            side: BorderSide(color: colors.border.withValues(alpha: 0.5)),
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SourceLogoAvatar(
                source: content.source,
                size: 24,
                radius: 6,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Article complet',
                  style: textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                PhosphorIcons.arrowDown(PhosphorIconsStyle.regular),
                size: 16,
                color: colors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Shimmer skeleton placeholder for the article body while content resolves.
  Widget _buildArticleBodySkeleton(FacteurColors colors) {
    final widths = [1.0, 1.0, 0.92, 1.0, 0.85, 1.0, 0.95, 0.6];
    return _ShimmerSkeleton(
      children: [
        const SizedBox(height: FacteurSpacing.space4),
        for (final w in widths)
          Padding(
            padding: const EdgeInsets.only(bottom: FacteurSpacing.space3),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: w,
              child: Container(
                height: 14,
                decoration: BoxDecoration(
                  color: colors.textTertiary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Progressive scroll-to-site layout (inverted stack architecture).
  /// WebView is fixed behind the scrollable article content.
  /// The opaque article container hides the WebView; transparent spacer reveals it.
  Widget _buildScrollToSiteContent(BuildContext context, Content content) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final viewportHeight = MediaQuery.of(context).size.height;
    final topInset = MediaQuery.of(context).padding.top;
    final headerHeight = topInset + _kHeaderContentHeight;
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    final availableHeight = viewportHeight - headerHeight;

    final articleText = content.htmlContent ?? content.description;
    final isPartial = isPartialContent(articleText);

    String? readingTime;
    if (content.durationSeconds != null && content.durationSeconds! > 0) {
      final minutes = (content.durationSeconds! / 60).ceil();
      readingTime = '$minutes min de lecture';
    }

    // Schedule offset computation after layout
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _computeScrollOffsets();
      }
    });

    return Stack(
      children: [
        // LAYER 0: WebView — fixed in viewport below the header, always rendered.
        // Painted first so it appears visually behind the scrollable content.
        Positioned(
          top: headerHeight,
          left: 0,
          right: 0,
          bottom: 0,
          child: _buildWebViewLayer(),
        ),

        // LAYER 1: Scrollable article content with opaque background.
        // Container color hides WebView entirely before CTA tap;
        // becomes transparent after tap so spacer reveals WebView.
        // IgnorePointer lets touches pass through to WebView when active.
        // AnimatedOpacity hides article layer when WebView is active to prevent
        // bottom-of-article content from bleeding through the header status bar area.
        // Once the fade completes, _articleLayerMounted flips to false and the
        // entire subtree is removed so Flutter no longer rasterizes it on top
        // of the scrolling WebView.
        if (_articleLayerMounted)
          Positioned.fill(
          child: AnimatedOpacity(
            opacity: _isWebViewActive ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 300),
            child: IgnorePointer(
              ignoring: _isWebViewActive,
              child: ColoredBox(
                color: _isWebViewActive
                    ? const Color(0x00000000)
                    : colors.backgroundPrimary,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  physics: _isWebViewActive
                      ? const NeverScrollableScrollPhysics()
                      : const ClampingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Spacer: scrolls with content, initially behind the header overlay
                      SizedBox(height: headerHeight),
                      // ZONE 1a: Top header (thumbnail / tags / title / reading-time)
                      Container(
                        color: colors.backgroundPrimary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: FacteurSpacing.space4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: FacteurSpacing.space2),
                            if (content.thumbnailUrl != null) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(
                                    FacteurRadius.large),
                                child: FacteurThumbnail(
                                  imageUrl: content.thumbnailUrl,
                                  aspectRatio: 16 / 9,
                                ),
                              ),
                              const SizedBox(height: FacteurSpacing.space3),
                            ],
                            if (isPartial ||
                                content.entities.isNotEmpty ||
                                content.topics.isNotEmpty) ...[
                              _buildTagsWrap(context, content,
                                  isPartial: isPartial),
                              const SizedBox(height: FacteurSpacing.space4),
                            ],
                            Text(
                              content.title,
                              style: textTheme.displayLarge
                                  ?.copyWith(fontSize: 24),
                            ),
                            const SizedBox(height: FacteurSpacing.space2),
                            if (readingTime != null) ...[
                              Row(
                                children: [
                                  Icon(
                                    PhosphorIcons.timer(
                                        PhosphorIconsStyle.regular),
                                    size: 14,
                                    color: colors.textTertiary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    readingTime,
                                    style: textTheme.bodySmall?.copyWith(
                                        color: colors.textTertiary),
                                  ),
                                ],
                              ),
                              const SizedBox(height: FacteurSpacing.space3),
                            ],
                            const SizedBox(height: FacteurSpacing.space4),
                          ],
                        ),
                      ),

                      // ZONE 1b: Perspectives section, framed by dividers.
                      if (_perspectivesResponse != null &&
                          _perspectivesResponse!.perspectives.isNotEmpty) ...[
                        Container(
                          color: colors.backgroundPrimary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: FacteurSpacing.space4),
                          child: Divider(color: colors.textTertiary.withValues(alpha: 0.3), height: 1, thickness: 1),
                        ),
                        Container(
                          color: colors.backgroundPrimary,
                          child: PerspectivesInlineSection(
                            key: _perspectivesKey,
                            perspectives: _perspectivesResponse!.perspectives
                                .map(
                                  (PerspectiveData p) => Perspective(
                                    title: p.title,
                                    url: p.url,
                                    sourceName: p.sourceName,
                                    sourceDomain: p.sourceDomain,
                                    biasStance: p.biasStance,
                                    publishedAt: p.publishedAt,
                                  ),
                                )
                                .toList(),
                            biasDistribution:
                                _perspectivesResponse!.biasDistribution,
                            keywords: _perspectivesResponse!.keywords,
                            sourceBiasStance:
                                _perspectivesResponse!.sourceBiasStance,
                            sourceName: _content?.source.name ?? '',
                            contentId: widget.contentId,
                            comparisonQuality:
                                _perspectivesResponse!.comparisonQuality,
                            externalSelectedSegments:
                                _perspectivesSelectedSegments,
                            onSegmentTap: _onPerspectivesSegmentTap,
                            onClearSegments: () {
                              setState(() =>
                                  _perspectivesSelectedSegments = {});
                            },
                            analysisState: _perspectivesAnalysisState,
                            analysisText: _perspectivesAnalysisText,
                            onRequestAnalysis: _requestPerspectivesAnalysis,
                            analysisZoneKey: _analysisZoneKey,
                            isExpanded: _perspectivesExpanded,
                            onToggle: _onPerspectivesToggle,
                          ),
                        ),
                        Container(
                          color: colors.backgroundPrimary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: FacteurSpacing.space4),
                          child: Divider(color: colors.textTertiary.withValues(alpha: 0.3), height: 1, thickness: 1),
                        ),
                      ],

                      // ZONE 2: Article body — _articleKey scopes scroll-bridge
                      // measurement to the body, excluding header + perspectives.
                      Container(
                        key: _articleKey,
                        color: colors.backgroundPrimary,
                        child: ArticleReaderWidget(
                          htmlContent: content.htmlContent,
                          description: content.description,
                          title: content.title,
                          shrinkWrap: true,
                          onLinkTap: _animateAndLaunch,
                          bodyPlaceholder: !_contentResolved
                              ? _buildArticleBodySkeleton(colors)
                              : null,
                          footer: SizedBox(
                              height: _kFooterContentHeight + bottomInset),
                        ),
                      ),

                      if (isPartial && _contentResolved)
                        _buildPartialArticleInlineButton(context, content),

                      // ZONE 3: Transparent spacer — only after CTA tap to enable scroll animation.
                      // _bridgeKey attached here so _computeScrollOffsets() can measure the bridge zone.
                      if (_ctaTapped)
                        SizedBox(key: _bridgeKey, height: availableHeight),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// WebView layer — fixed in viewport behind the scrollable content.
  Widget _buildWebViewLayer() {
    if (kIsWeb) return _buildWebViewFallback(_content!);

    // Initialize WebView if not already done (e.g. content loaded after init)
    if (_webViewController == null) {
      _initScrollToSiteWebView();
    }
    if (_webViewController == null) {
      return const SizedBox.shrink();
    }

    return WebViewWidget(
      controller: _webViewController!,
      gestureRecognizers: _isWebViewActive
          ? {
              Factory<VerticalDragGestureRecognizer>(
                  () => VerticalDragGestureRecognizer()),
              Factory<HorizontalDragGestureRecognizer>(
                  () => HorizontalDragGestureRecognizer()),
            }
          : const {},
    );
  }

  /// Video content layout.
  /// Regular videos: sticky 16:9 player at top, scrollable metadata below.
  /// Shorts: full-bleed 9:16 player with overlay metadata bar at bottom.
  Widget _buildVideoContent(BuildContext context, Content content) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final topInset = MediaQuery.of(context).padding.top;
    final headerHeight = topInset + _kHeaderContentHeight;
    final isShort = content.isShort;

    // Description text: prefer htmlContent (stripped), fallback to description
    final rawDescription = content.htmlContent ?? content.description;
    final descriptionText =
        rawDescription != null ? stripHtml(rawDescription).trim() : null;

    return LayoutBuilder(builder: (context, constraints) {
      final maxHeight = constraints.maxHeight;

      // --- Shorts: Column layout (no overlay on iframe → all buttons clickable) ---
      if (isShort) {
        // Reserve ~160px below the player for metadata (scrollable, same
        // pattern as regular videos). FABs float over this Flutter text area
        // (not an iframe) so they remain clickable.
        final shortsPlayerHeight =
            (maxHeight - headerHeight - 140).clamp(200.0, screenWidth * 16 / 9);

        return Column(
          children: [
            // Spacer for header overlay — collapses as header slides off so
            // the player fills the viewport up to the status bar.
            ValueListenableBuilder<double>(
              valueListenable: _headerOffset,
              builder: (_, offset, __) =>
                  SizedBox(height: headerHeight * (1.0 - offset)),
            ),

            // Centered player — bounded height, narrower than screen width
            SizedBox(
              height: shortsPlayerHeight,
              width: screenWidth,
              child: Center(
                child: YouTubePlayerWidget(
                  videoUrl: content.url,
                  title: content.title,
                  aspectRatio: 9 / 16,
                  onProgressChanged: _onVideoProgressChanged,
                  onPlayStateChanged: _onVideoPlayStateChanged,
                ),
              ),
            ),

            const SizedBox(height: FacteurSpacing.space3),

            // Scrollable metadata — same design as regular video
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: FacteurSpacing.space4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Video Title
                    Text(
                      content.title,
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: FacteurSpacing.space2),

                    // Published date
                    Text(
                      timeago.format(content.publishedAt, locale: 'fr_short'),
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: FacteurSpacing.space3),

                    // Channel row: avatar + name + optional theme chip
                    Row(
                      children: [
                        if (content.source.logoUrl != null)
                          CircleAvatar(
                            radius: 16,
                            backgroundImage: CachedNetworkImageProvider(
                                content.source.logoUrl!),
                            backgroundColor: colors.surfaceElevated,
                          )
                        else
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: colors.surfaceElevated,
                            child: Icon(
                              PhosphorIcons.user(PhosphorIconsStyle.regular),
                              size: 16,
                              color: colors.textTertiary,
                            ),
                          ),
                        const SizedBox(width: FacteurSpacing.space3),
                        Expanded(
                          child: Text(
                            content.source.name,
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (content.source.theme != null &&
                            content.source.theme!.isNotEmpty) ...[
                          const SizedBox(width: FacteurSpacing.space2),
                          Opacity(
                            opacity: 0.9,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: colors.primary,
                                borderRadius:
                                    BorderRadius.circular(FacteurRadius.pill),
                              ),
                              child: Text(
                                content.source.getThemeLabel(),
                                style: textTheme.labelSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),

                    // Expandable description
                    if (descriptionText != null &&
                        descriptionText.isNotEmpty) ...[
                      const SizedBox(height: FacteurSpacing.space3),
                      Divider(color: colors.border, height: 1),
                      const SizedBox(height: FacteurSpacing.space3),
                      Text(
                        descriptionText,
                        style: textTheme.bodyMedium?.copyWith(
                          color: colors.textSecondary,
                          height: 1.5,
                        ),
                        maxLines: _isDescriptionExpanded ? null : 2,
                        overflow: _isDescriptionExpanded
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: FacteurSpacing.space2),
                      GestureDetector(
                        onTap: () {
                          setState(() =>
                              _isDescriptionExpanded = !_isDescriptionExpanded);
                        },
                        child: Text(
                          _isDescriptionExpanded ? 'Voir moins' : 'Voir plus',
                          style: textTheme.bodySmall?.copyWith(
                            color: colors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],

                    // Bottom spacing — clears the persistent footer.
                    SizedBox(
                      height: _kFooterContentHeight +
                          MediaQuery.of(context).viewPadding.bottom,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      }

      // --- Regular video: Column layout ---
      final playerHeight = screenWidth * 9 / 16;

      return Column(
        children: [
          // Push below the header overlay — collapses with header slide.
          ValueListenableBuilder<double>(
            valueListenable: _headerOffset,
            builder: (_, offset, __) =>
                SizedBox(height: headerHeight * (1.0 - offset)),
          ),

          // Sticky player container
          SizedBox(
            width: screenWidth,
            height: playerHeight,
            child: YouTubePlayerWidget(
              videoUrl: content.url,
              title: content.title,
              aspectRatio: 16 / 9,
              onProgressChanged: _onVideoProgressChanged,
              onPlayStateChanged: _onVideoPlayStateChanged,
            ),
          ),

          // Scrollable metadata below the player
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(FacteurSpacing.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Video Title
                  Text(
                    content.title,
                    style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: FacteurSpacing.space2),

                  // Published date
                  Text(
                    timeago.format(content.publishedAt, locale: 'fr_short'),
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: FacteurSpacing.space4),

                  // Channel row: avatar + name + optional theme chip
                  Row(
                    children: [
                      if (content.source.logoUrl != null)
                        CircleAvatar(
                          radius: 16,
                          backgroundImage: CachedNetworkImageProvider(
                              content.source.logoUrl!),
                          backgroundColor: colors.surfaceElevated,
                        )
                      else
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: colors.surfaceElevated,
                          child: Icon(
                            PhosphorIcons.user(PhosphorIconsStyle.regular),
                            size: 16,
                            color: colors.textTertiary,
                          ),
                        ),
                      const SizedBox(width: FacteurSpacing.space3),
                      Expanded(
                        child: Text(
                          content.source.name,
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (content.source.theme != null &&
                          content.source.theme!.isNotEmpty) ...[
                        const SizedBox(width: FacteurSpacing.space2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: colors.primary,
                            borderRadius:
                                BorderRadius.circular(FacteurRadius.pill),
                          ),
                          child: Text(
                            content.source.getThemeLabel(),
                            style: textTheme.labelSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),

                  // Expandable description
                  if (descriptionText != null &&
                      descriptionText.isNotEmpty) ...[
                    const SizedBox(height: FacteurSpacing.space4),
                    Divider(color: colors.border, height: 1),
                    const SizedBox(height: FacteurSpacing.space4),
                    Text(
                      descriptionText,
                      style: textTheme.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                        height: 1.5,
                      ),
                      maxLines: _isDescriptionExpanded ? null : 3,
                      overflow: _isDescriptionExpanded
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: FacteurSpacing.space2),
                    GestureDetector(
                      onTap: () {
                        setState(() =>
                            _isDescriptionExpanded = !_isDescriptionExpanded);
                      },
                      child: Text(
                        _isDescriptionExpanded ? 'Voir moins' : 'Voir plus',
                        style: textTheme.bodySmall?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],

                  // Bottom spacing — clears the persistent footer.
                  SizedBox(
                    height: _kFooterContentHeight +
                        MediaQuery.of(context).viewPadding.bottom,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }); // LayoutBuilder
  }

  Widget _buildInAppContent(BuildContext context, Content content) {
    final topic = content.progressionTopic;

    if (topic != null) {
      // Logic for topic tracking can be added here if needed for analytics
      // but Footer CTA is removed per User Story 8 Refactor.
    }

    final topInset = MediaQuery.of(context).padding.top;
    final headerHeight = topInset + _kHeaderContentHeight;

    switch (content.contentType) {
      case ContentType.article:
        final colors = context.facteurColors;
        final textTheme = Theme.of(context).textTheme;
        final articleText = content.htmlContent ?? content.description;
        final isPartial = isPartialContent(articleText);

        String? readingTime;
        if (content.durationSeconds != null && content.durationSeconds! > 0) {
          final minutes = (content.durationSeconds! / 60).ceil();
          readingTime = '$minutes min de lecture';
        }

        // Pure HTML renderer — no header/footer props, layout is owned by the
        // outer Column below.
        final articleWidget = ArticleReaderWidget(
          htmlContent: content.htmlContent,
          description: content.description,
          title: content.title,
          shrinkWrap: true,
          onLinkTap: _animateAndLaunch,
          bodyPlaceholder:
              !_contentResolved ? _buildArticleBodySkeleton(colors) : null,
        );

        return ScrollConfiguration(
          // Hide the system scroll indicator — reading progress is shown by the
          // progress bar instead.
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: SingleChildScrollView(
            key: _scrollViewKey,
            controller: _inAppScrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header clearance ──────────────────────────────────────
                SizedBox(height: headerHeight),

                // ── Top section: thumbnail → chips → title → reading time ─
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: FacteurSpacing.space4),
                  child: Column(
                    spacing: 12,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (content.thumbnailUrl != null)
                        ClipRRect(
                          borderRadius:
                              BorderRadius.circular(FacteurRadius.large),
                          child: FacteurThumbnail(
                            imageUrl: content.thumbnailUrl,
                            aspectRatio: 16 / 9,
                          ),
                        ),
                      if (isPartial ||
                          content.entities.isNotEmpty ||
                          content.topics.isNotEmpty)
                        _buildTagsWrap(context, content, isPartial: isPartial),
                      Text(
                        content.title,
                        style: textTheme.displayLarge?.copyWith(fontSize: 24),
                      ),
                      if (readingTime != null)
                        Row(
                          children: [
                            Icon(
                              PhosphorIcons.timer(PhosphorIconsStyle.regular),
                              size: 14,
                              color: colors.textTertiary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              readingTime,
                              style: textTheme.bodySmall
                                  ?.copyWith(color: colors.textTertiary),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),

                // ── Perspectives section (avant l'article) ─────────────────
                if (_perspectivesResponse != null &&
                    _perspectivesResponse!.perspectives.isNotEmpty) ...[
                  const SizedBox(height: FacteurSpacing.space4),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: FacteurSpacing.space4),
                    child: Divider(color: colors.textTertiary.withValues(alpha: 0.3), height: 1, thickness: 1),
                  ),
                  PerspectivesInlineSection(
                    key: _perspectivesKey,
                    perspectives: _perspectivesResponse!.perspectives
                        .map(
                          (PerspectiveData p) => Perspective(
                            title: p.title,
                            url: p.url,
                            sourceName: p.sourceName,
                            sourceDomain: p.sourceDomain,
                            biasStance: p.biasStance,
                            publishedAt: p.publishedAt,
                          ),
                        )
                        .toList(),
                    biasDistribution: _perspectivesResponse!.biasDistribution,
                    keywords: _perspectivesResponse!.keywords,
                    sourceBiasStance: _perspectivesResponse!.sourceBiasStance,
                    sourceName: _content?.source.name ?? '',
                    contentId: widget.contentId,
                    comparisonQuality:
                        _perspectivesResponse!.comparisonQuality,
                    externalSelectedSegments: _perspectivesSelectedSegments,
                    onSegmentTap: _onPerspectivesSegmentTap,
                    onClearSegments: () {
                      setState(() => _perspectivesSelectedSegments = {});
                    },
                    analysisState: _perspectivesAnalysisState,
                    analysisText: _perspectivesAnalysisText,
                    onRequestAnalysis: _requestPerspectivesAnalysis,
                    analysisZoneKey: _analysisZoneKey,
                    isExpanded: _perspectivesExpanded,
                    onToggle: _onPerspectivesToggle,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: FacteurSpacing.space4),
                    child: Divider(color: colors.textTertiary.withValues(alpha: 0.3), height: 1, thickness: 1),
                  ),
                ],

                const SizedBox(height: FacteurSpacing.space4),

                // ── Article section ────────────────────────────────────────
                // Zero-height marker at the end lets _measureArticleExtent()
                // compute progress against article length only (excludes perspectives).
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    articleWidget,
                    if (isPartial && _contentResolved)
                      _buildPartialArticleInlineButton(context, content),
                    if (_showReadOnSiteNudge) ...[
                      const SizedBox(height: FacteurSpacing.space4),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: FacteurSpacing.space4),
                        child: NudgeInlineBanner(
                          body:
                              "Préférez l'expérience du site original ? Ouvrez l'article dans votre navigateur.",
                          icon: PhosphorIcons.arrowSquareOut(),
                          actionLabel: 'Ouvrir',
                          onAction: () {
                            _dismissReadOnSiteNudge(converted: true);
                            _openOriginalUrl();
                          },
                          onDismiss: () =>
                              _dismissReadOnSiteNudge(converted: false),
                        ),
                      ),
                    ],
                    SizedBox(key: _articleEndKey, height: 0),
                  ],
                ),

                // ── Footer clearance ───────────────────────────────────────
                const SizedBox(height: FacteurSpacing.space4),
                SizedBox(
                  height: _kFooterContentHeight +
                      MediaQuery.of(context).viewPadding.bottom,
                ),
              ],
            ),
          ),
        );

      case ContentType.audio:
        final audioBottomInset =
            _kFooterContentHeight + MediaQuery.of(context).viewPadding.bottom;
        return Column(
          children: [
            ValueListenableBuilder<double>(
              valueListenable: _headerOffset,
              builder: (_, offset, __) =>
                  SizedBox(height: headerHeight * (1.0 - offset)),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: audioBottomInset),
                child: AudioPlayerWidget(
                  audioUrl: content.audioUrl!,
                  title: content.title,
                  description: content.description,
                  thumbnailUrl: content.thumbnailUrl,
                  durationSeconds: content.durationSeconds,
                ),
              ),
            ),
          ],
        );

      case ContentType.youtube:
      case ContentType.video:
        final videoBottomInset =
            _kFooterContentHeight + MediaQuery.of(context).viewPadding.bottom;
        return Column(
          children: [
            ValueListenableBuilder<double>(
              valueListenable: _headerOffset,
              builder: (_, offset, __) =>
                  SizedBox(height: headerHeight * (1.0 - offset)),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: videoBottomInset),
                child: YouTubePlayerWidget(
                  videoUrl: content.url,
                  title: content.title,
                  description: content.description,
                ),
              ),
            ),
          ],
        );
    }
  }

  Widget _buildWebViewFallback(Content content) {
    final colors = context.facteurColors;

    // Legacy web fallback — unreachable since build() auto-redirects
    // and footer CTA opens externally on web. Kept as safety net.
    if (kIsWeb) {
      return Center(
        child: CircularProgressIndicator(color: colors.primary),
      );
    }

    // Mobile: Use native WebView with ScrollBridge for progress + auto-hide
    _webViewController ??= WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => _injectScrollBridgeScript(),
      ))
      ..addJavaScriptChannel('ScrollBridge',
          onMessageReceived: _onScrollBridgeMessage)
      ..loadRequest(Uri.parse(content.url));

    final topInset = MediaQuery.of(context).padding.top;
    final headerHeight = topInset + _kHeaderContentHeight;
    return Column(
      children: [
        ValueListenableBuilder<double>(
          valueListenable: _headerOffset,
          builder: (_, offset, __) =>
              SizedBox(height: headerHeight * (1.0 - offset)),
        ),
        // Extra breathing room so tag chips aren't clipped by the header overlay
        const SizedBox(height: FacteurSpacing.space2),
        if (content.entities.isNotEmpty || content.topics.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: FacteurSpacing.space4, vertical: 6),
            child: _buildTagsWrap(context, content),
          ),
        Expanded(child: WebViewWidget(controller: _webViewController!)),
      ],
    );
  }
}

/// Subtle periodic nudge on the source badge to hint at long-press.
/// Compact "+ Suivre" chip shown in the reader header when the article's
/// source is not yet followed. Tap = optimistic follow via
/// [userSourcesStateProvider]; the chip vanishes on the next rebuild because
/// the live state flips to [InterestState.followed].
class _FollowSourceChip extends ConsumerStatefulWidget {
  final String sourceId;
  final FacteurColors colors;

  const _FollowSourceChip({required this.sourceId, required this.colors});

  @override
  ConsumerState<_FollowSourceChip> createState() => _FollowSourceChipState();
}

class _FollowSourceChipState extends ConsumerState<_FollowSourceChip> {
  bool _busy = false;

  Future<void> _onTap() async {
    if (_busy) return;
    setState(() => _busy = true);
    HapticFeedback.lightImpact();
    try {
      await ref
          .read(userSourcesStateProvider.notifier)
          .setSourceState(widget.sourceId, InterestState.followed);
      if (!mounted) return;
      NotificationService.showSuccess(
        'Source ajoutée à votre veille',
        context: context,
      );
    } catch (e) {
      if (!mounted) return;
      NotificationService.showError(
        'Impossible de suivre la source',
        context: context,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    return Material(
      color: c.primary,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _busy ? null : _onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_busy)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              else
                const Icon(Icons.add, size: 14, color: Colors.white),
              const SizedBox(width: 4),
              Text(
                'Suivre',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceBadgeNudge extends StatefulWidget {
  final Widget child;

  const _SourceBadgeNudge({required this.child});

  @override
  State<_SourceBadgeNudge> createState() => _SourceBadgeNudgeState();
}

class _SourceBadgeNudgeState extends State<_SourceBadgeNudge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final math.Random _rng = math.Random();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _scheduleNext();
      }
    });
    _scheduleNext();
  }

  void _scheduleNext() {
    final delayMs = 8000 + _rng.nextInt(7000); // 8–15 s
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: delayMs), () {
      if (mounted) _controller.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = 1.0 + 0.02 * math.sin(_controller.value * math.pi);
        return Transform.scale(scale: scale, child: child);
      },
      child: widget.child,
    );
  }
}

/// Pulsating shimmer effect for skeleton loading placeholders.
class _ShimmerSkeleton extends StatefulWidget {
  final List<Widget> children;
  const _ShimmerSkeleton({required this.children});

  @override
  State<_ShimmerSkeleton> createState() => _ShimmerSkeletonState();
}

class _ShimmerSkeletonState extends State<_ShimmerSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
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
        return Opacity(
          opacity: 0.3 + 0.4 * _controller.value,
          child: child,
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: widget.children,
      ),
    );
  }
}

class _FadeScrollRow extends StatefulWidget {
  final List<Widget> children;

  const _FadeScrollRow({required this.children});

  @override
  State<_FadeScrollRow> createState() => _FadeScrollRowState();
}

class _FadeScrollRowState extends State<_FadeScrollRow> {
  final _controller = ScrollController();
  bool _atStart = true;
  bool _atEnd = false;
  bool _pointerDown = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final pos = _controller.position;
    final atStart = pos.pixels <= 0;
    final atEnd = pos.pixels >= pos.maxScrollExtent;
    if (atStart != _atStart || atEnd != _atEnd) {
      setState(() {
        _atStart = atStart;
        _atEnd = atEnd;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: PopScope(
        canPop: _atStart || !_pointerDown,
        child: Listener(
          onPointerDown: (_) => setState(() => _pointerDown = true),
          onPointerUp: (_) => setState(() => _pointerDown = false),
          onPointerCancel: (_) => setState(() => _pointerDown = false),
          child: ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                _atStart ? Colors.white : Colors.transparent,
                Colors.white,
                Colors.white,
                _atEnd ? Colors.white : Colors.transparent,
              ],
              stops: const [0.0, 0.12, 0.82, 1.0],
            ).createShader(bounds),
            blendMode: BlendMode.dstIn,
            child: NotificationListener<ScrollNotification>(
              onNotification: (_) => true,
              child: SingleChildScrollView(
                controller: _controller,
                scrollDirection: Axis.horizontal,
                child: Row(
                  spacing: 6,
                  children: widget.children,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
