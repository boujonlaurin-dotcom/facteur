import 'package:cached_network_image/cached_network_image.dart';
import 'package:facteur/core/utils/html_utils.dart';
import 'package:flutter/foundation.dart' show Factory, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
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
import '../../sources/providers/sources_providers.dart';
import '../../feed/widgets/perspectives_pill.dart';
import '../../../widgets/sunflower_icon.dart';
import '../providers/nudge_provider.dart' show NudgeTracker;
import '../widgets/article_reader_widget.dart';
import '../widgets/audio_player_widget.dart';
import '../widgets/youtube_player_widget.dart';
import '../widgets/note_input_sheet.dart';
import '../widgets/note_welcome_tooltip.dart';
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
/// = top padding (16) + icon row (~34) + bottom padding (8).
const double _kHeaderContentHeight = 58;

/// Height of the footer content area (above the safe-area bottom inset).
/// = vertical padding (12+12) + button row height (44).
const double _kFooterContentHeight = 82.0;

/// Bottom scroll clearance so content isn't hidden behind the FAB row.
const double _kFabBottomClearance = 120.0;

class _ContentDetailScreenState extends ConsumerState<ContentDetailScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _fabController;
  late Animation<double> _fabAnimation;
  late AnimationController _bookmarkBounceController;
  late Animation<double> _bookmarkScaleAnimation;
  late AnimationController _likeBounceController;
  late Animation<double> _likeScaleAnimation;
  late AnimationController _fabReappearController;
  late Animation<double> _fabReappearScale;
  late AnimationController _shareFabController;
  late Animation<double> _shareFabScale;
  late AnimationController _exitAnimController;
  bool _isExitAnimating = false;

  bool _showFab = false;
  bool _showShareFab = false;
  bool _isShortArticle = false;
  bool _footerPermanent =
      false; // true once user reaches end of displayed content
  final ValueNotifier<bool> _atPerspectivesSection = ValueNotifier(false);
  bool _showNoteWelcome = false;
  bool _linkCopiedFab = false;
  bool _linkCopiedHeader = false;
  Timer? _linkCopiedFabTimer;
  Timer? _linkCopiedHeaderTimer;
  bool _premiumRedirectScheduled = false;
  bool _webFallbackRedirectScheduled = false;
  late DateTime _startTime;
  WebViewController? _webViewController;
  final bool _showWebView = false;

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

  final ValueNotifier<double> _fabOpacity = ValueNotifier<double>(0.07);

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

  // Video detail screen state
  bool _isDescriptionExpanded = false;
  bool _isVideoPlaying = false;
  Timer? _videoPlayHideTimer;

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

  // Perspectives sticky section header state
  Set<String> _perspectivesSelectedSegments = {};
  final ValueNotifier<bool> _showStickyPerspectivesHeader =
      ValueNotifier(false);

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

    _fabController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fabAnimation = CurvedAnimation(
      parent: _fabController,
      curve: Curves.easeOut,
    );

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

    // Scroll reappear: subtle scale-up when FABs fade back in
    _fabReappearController = AnimationController(
      duration: const Duration(milliseconds: 400),
      value: 1.0, // Start at end so initial scale is 1.0
      vsync: this,
    );
    _fabReappearScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.85, end: 1.05)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.05, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 40,
      ),
    ]).animate(_fabReappearController);

    // Share FAB entrance animation (triggered at 90% reading progress)
    _shareFabController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _shareFabScale = CurvedAnimation(
      parent: _shareFabController,
      curve: Curves.elasticOut,
    );

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

    WidgetsBinding.instance.addObserver(this);

    // Show FAB after delay — start transparent, fade+scale in after 2s
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (mounted) {
        setState(() {
          _showFab = true;
        });
        _fabOpacity.value = 1.0;
        _fabController.forward();
      }
    });

    // Check if note welcome tooltip should be shown (first time only)
    NoteWelcomeTooltip.shouldShow().then((show) {
      if (mounted && show) {
        setState(() => _showNoteWelcome = true);
      }
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

    // Share FAB: show only after 90% reading on long articles
    _readingProgress.addListener(_onShareFabProgress);

    // Detect short articles after first layout
    WidgetsBinding.instance.addPostFrameCallback((_) {
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

  /// Inject JS to detect overscroll at top + track reading progress.
  Future<void> _injectScrollBridgeScript() async {
    if (_webViewController == null) return;
    await _webViewController!.runJavaScript('''
      (function() {
        var lastTouchY = 0;
        var lastProgress = 0;
        document.addEventListener('touchstart', function(e) {
          lastTouchY = e.touches[0].clientY;
        }, { passive: true });
        document.addEventListener('touchmove', function(e) {
          var currentY = e.touches[0].clientY;
          var isScrollingUp = currentY > lastTouchY;
          if (isScrollingUp && window.scrollY <= 0) {
            ScrollBridge.postMessage('overscroll_top');
          }
          lastTouchY = currentY;
        }, { passive: true });
        // Reading progress tracking (throttled to every 150ms for smooth updates)
        var progressTimer = null;
        var lastScrollY = window.scrollY;
        window.addEventListener('scroll', function() {
          if (progressTimer) return;
          progressTimer = setTimeout(function() {
            progressTimer = null;
            var maxScroll = document.documentElement.scrollHeight - window.innerHeight;
            if (maxScroll > 0) {
              var pct = parseFloat((window.scrollY / maxScroll * 100).toFixed(1));
              pct = Math.min(100, Math.max(0, pct));
              if (pct !== lastProgress) {
                lastProgress = pct;
                ScrollBridge.postMessage('progress:' + pct);
              }
            }
            var currentScrollY = window.scrollY;
            var scrollDelta = currentScrollY - lastScrollY;
            if (scrollDelta !== 0) {
              ScrollBridge.postMessage('scroll_delta:' + scrollDelta + ':' + currentScrollY);
            }
            lastScrollY = currentScrollY;
          }, 150);
        }, { passive: true });
      })();
    ''');
  }

  /// Handle messages from the WebView JS bridge.
  void _onScrollBridgeMessage(JavaScriptMessage message) {
    final msg = message.message;
    if (msg.startsWith('scroll_delta:')) {
      final parts = msg.substring(13).split(':');
      final delta = double.tryParse(parts[0]);
      if (delta != null) {
        if (parts.length > 1) {
          _webScrollY = double.tryParse(parts[1]) ?? _webScrollY;
        }
        _onScrollDelta(delta);
      }
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
  }

  /// Show header + footer when user reaches the bottom of the article (progress ≥ 98%).
  void _onReadingProgressNudge() {
    if (_readingProgress.value >= 0.98) {
      _inactivityTimer?.cancel();
      if (_headerOffset.value > 0.0) _animateHeaderTo(0.0);
      if (_footerOffset.value > 0.0) _animateFooterTo(0.0);
    }
  }

  /// Show Share FAB when user reaches 90% of article (long articles only).
  void _onShareFabProgress() {
    if (_showShareFab || _isShortArticle) return;
    if (_maxReadingProgress >= 0.9) {
      setState(() => _showShareFab = true);
      _shareFabController.forward();
    }
  }

  /// Detect short articles that don't need scrolling.
  void _checkShortArticle() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.maxScrollExtent < 50) {
      _isShortArticle = true;
      _footerPermanent = true;
    }
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

  /// Updates [_atPerspectivesSection] based on whether the perspectives widget
  /// is visible in the viewport. Called from the scroll notification handler.
  /// Uses ValueNotifier to avoid triggering a full setState during scroll.
  void _checkAtPerspectivesSection() {
    final ctx = _perspectivesKey.currentContext;
    if (ctx == null) return;
    final perspBox = ctx.findRenderObject() as RenderBox?;
    if (perspBox == null || !perspBox.hasSize) return;

    final perspScreenY = perspBox.localToGlobal(Offset.zero).dy;
    final screenHeight = MediaQuery.of(context).size.height;
    final reached = perspScreenY < screenHeight * 0.85;

    if (reached != _atPerspectivesSection.value) {
      _atPerspectivesSection.value = reached;
      // Footer becomes sticky as soon as the perspectives section is reached.
      if (reached && !_footerPermanent) {
        _footerPermanent = true;
        _animateFooterTo(0.0);
      }
    }

    // Sticky perspectives header: show as soon as the section title has
    // scrolled above the bottom of the app header.
    final appHeaderHeight =
        MediaQuery.of(context).padding.top + _kHeaderContentHeight;
    final appHeaderBottomY = appHeaderHeight * (1.0 - _headerOffset.value);
    final shouldStick = perspScreenY < appHeaderBottomY;
    if (shouldStick != _showStickyPerspectivesHeader.value) {
      _showStickyPerspectivesHeader.value = shouldStick;
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
    // Re-check sticky visibility after the section has rebuilt (filtering may
    // shrink the section back into view with no scroll event).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _checkAtPerspectivesSection();
    });
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
    }
  }

  /// Fade FABs + header during scroll, restore on stop with differentiated delays.
  /// Uses ValueNotifier to avoid rebuilding the entire widget tree on each scroll pixel.
  /// Auto-hide header/FABs during video playback for immersion.
  void _onVideoPlayStateChanged(bool isPlaying) {
    _isVideoPlaying = isPlaying;
    _videoPlayHideTimer?.cancel();

    if (isPlaying) {
      _videoPlayHideTimer = Timer(const Duration(milliseconds: 2500), () {
        if (mounted && _isVideoPlaying) {
          // Keep header visible in video readers (fullscreen is handled natively).
          _fabOpacity.value = 0.07;
        }
      });
    } else {
      _headerOffset.value = 0.0;
      _fabOpacity.value = 1.0;

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

  /// Update header offset and FAB opacity based on scroll delta (in pixels).
  /// Positive delta = scrolling down, negative = scrolling up.
  void _onScrollDelta(double delta) {
    // Dismiss sunflower nudge on any scroll
    if (_showSunflowerNudge) {
      setState(() => _showSunflowerNudge = false);
    }
    final isVideo = _content?.isVideo ?? false;
    _videoPlayHideTimer?.cancel();
    if (_fabOpacity.value != 0.07) {
      _fabOpacity.value = 0.07;
    }
    // In video readers the header stays visible at all times (only native
    // fullscreen covers it, which is handled by the system).
    // For short articles that don't need scrolling, keep header visible.
    if (!isVideo && !_isShortArticle) {
      final headerHeight =
          MediaQuery.of(context).padding.top + _kHeaderContentHeight;
      final shift = delta / headerHeight;
      _headerOffset.value = (_headerOffset.value + shift).clamp(0.0, 1.0);

      // Footer mirrors header: hides on scroll-down, shows on scroll-up.
      // Skipped once the user has reached the end of the displayed content.
      if (!_footerPermanent) {
        final bottomInset = MediaQuery.of(context).viewPadding.bottom;
        final footerHeight = _kFooterContentHeight + bottomInset;
        final footerShift = delta / footerHeight;
        _footerOffset.value =
            (_footerOffset.value + footerShift).clamp(0.0, 1.0);
      }
    }
    // FABs + footer reappear after 2.5s of scroll inactivity
    _scrollStopTimer?.cancel();
    _scrollStopTimer = Timer(const Duration(milliseconds: 2000), () {
      if (mounted) {
        _fabOpacity.value = 1.0;
        _fabReappearController.forward(from: 0);
        _animateFooterTo(0.0);
      }
    });
    // Auto-hide header after 3s of inactivity (no scroll), but only if not at top
    _inactivityTimer?.cancel();
    if (!isVideo && !_isShortArticle) {
      _inactivityTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && _webScrollY > 0 && _headerOffset.value < 1.0) {
          _animateHeaderTo(1.0);
        }
      });
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
          // Re-check short article + measure article extent after content loads and renders
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _checkShortArticle();
              _measureArticleExtent();
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

  Future<void> _shareArticle({bool isFab = false}) async {
    final content = _content;
    if (content == null) return;

    await Clipboard.setData(ClipboardData(text: content.url));
    if (mounted) {
      if (isFab) {
        setState(() => _linkCopiedFab = true);
        _linkCopiedFabTimer?.cancel();
        _linkCopiedFabTimer = Timer(const Duration(seconds: 2), () {
          if (mounted) setState(() => _linkCopiedFab = false);
        });
      } else {
        setState(() => _linkCopiedHeader = true);
        _linkCopiedHeaderTimer?.cancel();
        _linkCopiedHeaderTimer = Timer(const Duration(seconds: 2), () {
          if (mounted) setState(() => _linkCopiedHeader = false);
        });
      }
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

  @override
  void dispose() {
    // Capture max progress reached before disposing ValueNotifier
    final progressPct = (_maxReadingProgress * 100).round().clamp(0, 100);

    // Persist reading progress + analytics on close.
    // Must happen before super.dispose() — ref.read() requires active ConsumerState.
    try {
      if (_content != null) {
        final duration = DateTime.now().difference(_startTime).inSeconds;

        // Persist reading progress via status endpoint
        if (progressPct > 0) {
          final supabase = Supabase.instance.client;
          final apiClient = ApiClient(supabase);
          final repository = FeedRepository(apiClient);
          repository.updateContentStatusWithProgress(
            _content!.id,
            progressPct,
          );
        }

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
    _videoPlayHideTimer?.cancel();
    _linkCopiedFabTimer?.cancel();
    _linkCopiedHeaderTimer?.cancel();
    _fabController.dispose();
    _bookmarkBounceController.dispose();
    _likeBounceController.dispose();
    _fabReappearController.dispose();
    _shareFabController.dispose();
    _exitAnimController.dispose();
    _headerAutoController.dispose();
    _footerAutoController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _fabOpacity.dispose();
    _headerOffset.dispose();
    _footerOffset.dispose();
    _readingProgress.removeListener(_onReadingProgressNudge);
    _readingProgress.removeListener(_onShareFabProgress);
    _readingProgress.dispose();
    _scrollController.removeListener(_onScrollToSite);
    _scrollController.removeListener(_onScrollReadingProgress);

    _atPerspectivesSection.dispose();
    _showStickyPerspectivesHeader.dispose();
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
        });
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

  /// Show perspectives bottom sheet — uses pre-loaded data if available
  Future<void> _showPerspectives(BuildContext context) async {
    final content = _content;
    if (content == null) return;

    // If data already pre-loaded, show directly
    if (_perspectivesResponse != null) {
      _showPerspectivesSheet(context, _perspectivesResponse!);
      return;
    }

    // Otherwise fetch with loading indicator
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: 200,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              const SizedBox(height: FacteurSpacing.space4),
              Text('Recherche de perspectives...'),
            ],
          ),
        ),
      ),
    );

    try {
      final repository = ref.read(feedRepositoryProvider);

      final response = await repository.getPerspectives(content.id);

      if (context.mounted) Navigator.pop(context);

      if (context.mounted) {
        setState(() => _perspectivesResponse = response);
        _showPerspectivesSheet(context, response);
      }
    } catch (e) {
      debugPrint('Error fetching perspectives: $e');
      if (context.mounted) Navigator.pop(context);
      if (context.mounted) {
        NotificationService.showError('Impossible de charger les perspectives',
            context: context);
      }
    }
  }

  void _showPerspectivesSheet(
      BuildContext context, PerspectivesResponse response) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PerspectivesBottomSheet(
        perspectives: response.perspectives
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
        biasDistribution: response.biasDistribution,
        keywords: response.keywords,
        sourceBiasStance: response.sourceBiasStance,
        sourceName: _content?.source.name ?? '',
        contentId: widget.contentId,
        comparisonQuality: response.comparisonQuality,
      ),
    );
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
                  // Sync short-article flag from live scroll metrics (catches cases
                  // where the postFrameCallback hasn't fired yet).
                  if (!_isShortArticle &&
                      notification.metrics.maxScrollExtent < 50) {
                    _isShortArticle = true;
                    _footerPermanent = true;
                    _headerOffset.value = 0.0;
                  }
                  _onScrollDelta(delta);
                  _checkAtPerspectivesSection();
                  // Track reading progress from any scrollable (including in-app reader)
                  final metrics = notification.metrics;
                  if (metrics.maxScrollExtent > 0) {
                    final rawProgress =
                        metrics.pixels / metrics.maxScrollExtent;
                    // Footer becomes permanent at end of ALL content (incl. perspectives)
                    if (!_footerPermanent && rawProgress >= 0.98) {
                      _footerPermanent = true;
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
                child: _buildHeader(context, content),
              ),
            ),
            // Opaque status-bar backdrop — only when WebView is active and
            // the header has slid off-screen, so WebView content doesn't
            // bleed through the transparent status bar zone.
            if (_isWebViewActive)
              ValueListenableBuilder<double>(
                valueListenable: _headerOffset,
                builder: (context, offset, _) {
                  final statusBarHeight = MediaQuery.of(context).padding.top;
                  return Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: offset,
                        child: SizedBox(
                          height: statusBarHeight,
                          child: ColoredBox(color: colors.backgroundPrimary),
                        ),
                      ),
                    ),
                  );
                },
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
                      statusBarHeight + _kHeaderContentHeight;
                  final topWhenHeaderHidden = statusBarHeight;
                  final top = topWhenHeaderVisible -
                      offset * (topWhenHeaderVisible - topWhenHeaderHidden);
                  return Positioned(
                    top: top,
                    left: 0,
                    right: 0,
                    child: _buildReadingProgressBar(colors),
                  );
                },
              ),
            // Sticky perspectives section header — appears below the app header
            // when the inline section header has scrolled off-screen.
            // Only shown for in-app article reading.
            if (useInAppReading &&
                content.contentType == ContentType.article &&
                _perspectivesResponse != null)
              ValueListenableBuilder<bool>(
                valueListenable: _showStickyPerspectivesHeader,
                builder: (context, showSticky, _) {
                  return ValueListenableBuilder<double>(
                    valueListenable: _headerOffset,
                    builder: (context, offset, _) {
                      final statusBarHeight =
                          MediaQuery.of(context).padding.top;
                      // Sits immediately below the reading progress bar (+2px).
                      final topWhenHeaderVisible =
                          statusBarHeight + _kHeaderContentHeight + 2.0;
                      final topWhenHeaderHidden = statusBarHeight + 2.0;
                      final top = topWhenHeaderVisible -
                          offset * (topWhenHeaderVisible - topWhenHeaderHidden);
                      return Positioned(
                        top: top,
                        left: 0,
                        right: 0,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: showSticky ? 1.0 : 0.0,
                          child: IgnorePointer(
                            ignoring: !showSticky,
                            child: _buildPerspectivesStickyHeader(
                                context, _perspectivesResponse!),
                          ),
                        ),
                      );
                    },
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
            // Visible when the perspectives section is on screen and analysis
            // hasn't been triggered yet.
            if (useInAppReading && content.contentType == ContentType.article)
              Positioned(
                right: 16,
                bottom: _kFooterContentHeight +
                    MediaQuery.of(context).viewPadding.bottom +
                    12,
                child: ValueListenableBuilder<bool>(
                  valueListenable: _atPerspectivesSection,
                  builder: (context, atPersp, _) {
                    final show = atPersp &&
                        _perspectivesAnalysisState ==
                            PerspectivesAnalysisState.idle &&
                        _perspectivesResponse != null &&
                        _perspectivesResponse!.perspectives.isNotEmpty;
                    return AnimatedOpacity(
                      opacity: show ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: IgnorePointer(
                        ignoring: !show,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.85),
                                blurRadius: 0,
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
                              side: BorderSide(
                                color: context.facteurColors.primary,
                              ),
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.5),
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
                    );
                  },
                ),
              ),
            // Footer — shown for in-app article reading, mirrors header slide behavior
            if (useScrollToSite ||
                (useInAppReading && content.contentType == ContentType.article))
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildArticleFooter(context, content),
              ),
          ],
        ),
      ),
      // FABs — vertical column with immersive scroll opacity
      // Suppressed for articles (replaced by the persistent footer).
      // ValueListenableBuilder isolates FAB opacity rebuilds from the main widget tree.
      floatingActionButton: _showFab &&
              !useScrollToSite &&
              !(useInAppReading && content.contentType == ContentType.article)
          ? ValueListenableBuilder<double>(
              valueListenable: _fabOpacity,
              builder: (context, opacity, child) => AnimatedOpacity(
                opacity: opacity,
                duration: Duration(milliseconds: opacity < 1.0 ? 150 : 300),
                child: ScaleTransition(
                  scale: _fabAnimation,
                  child: ScaleTransition(
                    scale: _fabReappearScale,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Share FAB — appears after 90% reading on long articles
                        if (_showShareFab) ...[
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              if (_linkCopiedFab) ...[
                                _buildLinkCopiedTooltip(context),
                                const SizedBox(width: 16),
                              ],
                              ScaleTransition(
                                scale: _shareFabScale,
                                child: SizedBox(
                                  width: 50,
                                  height: 50,
                                  child: FloatingActionButton(
                                    onPressed: () => _shareArticle(isFab: true),
                                    backgroundColor: Colors.white,
                                    foregroundColor: colors.textPrimary,
                                    elevation: 2,
                                    heroTag: 'share_fab',
                                    tooltip: 'Partager',
                                    child: Icon(
                                      PhosphorIcons.shareNetwork(
                                          PhosphorIconsStyle.regular),
                                      size: 25,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: FacteurSpacing.space3),
                        ],
                        // Perspectives FAB (articles only) — always just above other FABs
                        if (content.contentType == ContentType.article) ...[
                          PerspectivesPill(
                            biasDistribution:
                                _perspectivesResponse?.biasDistribution ?? {},
                            isLoading: _perspectivesLoading,
                            isEmpty: !_perspectivesLoading &&
                                _perspectivesResponse != null &&
                                _perspectivesResponse!.perspectives.isEmpty,
                            onTap: () {
                              HapticFeedback.lightImpact();
                              final ctx = _perspectivesKey.currentContext;
                              if (ctx != null) {
                                Scrollable.ensureVisible(
                                  ctx,
                                  duration: const Duration(milliseconds: 400),
                                  curve: Curves.easeInOut,
                                );
                              } else {
                                _showPerspectives(context);
                              }
                            },
                          ),
                          const SizedBox(height: FacteurSpacing.space3),
                        ],
                        // External link FAB — hidden for articles unless WebView is active
                        if (content.contentType != ContentType.article ||
                            _showWebView ||
                            _isWebViewActive) ...[
                          SizedBox(
                            width: 50,
                            height: 50,
                            child: FloatingActionButton(
                              onPressed: _openOriginalUrl,
                              backgroundColor: Colors.white,
                              foregroundColor: colors.textPrimary,
                              elevation: 2,
                              heroTag: 'original_fab',
                              tooltip: _getFabLabel(),
                              child: Icon(
                                PhosphorIcons.arrowSquareOut(
                                    PhosphorIconsStyle.regular),
                                size: 25,
                              ),
                            ),
                          ),
                          const SizedBox(height: FacteurSpacing.space3),
                        ],
                        // 🌻 Sunflower recommendation FAB
                        ScaleTransition(
                          scale: _likeScaleAnimation,
                          child: SizedBox(
                            width: 50,
                            height: 50,
                            child: FloatingActionButton(
                              onPressed: _toggleLike,
                              backgroundColor: content.isLiked
                                  ? colors.primary
                                  : Colors.white,
                              foregroundColor: content.isLiked
                                  ? Colors.white
                                  : colors.textPrimary,
                              elevation: content.isLiked ? 4 : 2,
                              heroTag: 'sunflower_fab',
                              tooltip: 'Recommander',
                              child: SunflowerIcon(
                                isActive: content.isLiked,
                                size: 25,
                                inactiveColor: colors.textPrimary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: FacteurSpacing.space3),
                        // Merged Bookmark + Note FAB (long-press for collection picker)
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
                            child: SizedBox(
                              width: 50,
                              height: 50,
                              child: FloatingActionButton(
                                onPressed: _toggleBookmark,
                                backgroundColor: content.isSaved
                                    ? colors.primary
                                    : Colors.white,
                                foregroundColor: content.isSaved
                                    ? Colors.white
                                    : colors.textPrimary,
                                elevation: content.isSaved ? 4 : 2,
                                heroTag: 'bookmark_fab',
                                tooltip: 'Sauvegarder',
                                child: Icon(
                                  content.isSaved
                                      ? PhosphorIcons.bookmarkSimple(
                                          PhosphorIconsStyle.fill)
                                      : PhosphorIcons.bookmarkSimple(
                                          PhosphorIconsStyle.regular),
                                  size: 25,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Note welcome tooltip — bottom of FAB column, near the bookmark button
                        if (_showNoteWelcome) ...[
                          const SizedBox(height: FacteurSpacing.space3),
                          NoteWelcomeTooltip(
                            onDismiss: () =>
                                setState(() => _showNoteWelcome = false),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
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
    } else {
      _openOriginalUrl();
    }
  }

  /// Persistent footer bar shown for in-app article reading.
  /// Mirrors header slide behavior: hides on scroll-down, shows on scroll-up.
  Widget _buildArticleFooter(BuildContext context, Content content) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;

    const iconButtonStyle = ButtonStyle(
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      padding: WidgetStatePropertyAll(EdgeInsets.all(12)),
      minimumSize: WidgetStatePropertyAll(Size(56, 56)),
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
              // "Lire sur [Source]" — fills available space
              Expanded(
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
                      side: BorderSide(
                          color: colors.border.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: Row(
                      children: [
                        if (content.source.logoUrl != null) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(
                              imageUrl: content.source.logoUrl!,
                              width: 28,
                              height: 28,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) =>
                                  const SizedBox.shrink(),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            'Lire sur ${content.source.name}',
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
                          PhosphorIcons.arrowRight(PhosphorIconsStyle.regular),
                          size: 16,
                          color: colors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),

              // Autres points de vue / Retour à l'article
              ValueListenableBuilder<bool>(
                valueListenable: _atPerspectivesSection,
                builder: (context, atPersp, _) {
                  if (atPersp) {
                    return Tooltip(
                      message: 'Retour à l\'article',
                      child: IconButton(
                        style: iconButtonStyle,
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          _atPerspectivesSection.value = false;
                          if (_inAppScrollController.hasClients) {
                            _inAppScrollController.animateTo(
                              0,
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeInOut,
                            );
                          }
                        },
                        icon: Icon(
                          PhosphorIcons.newspaper(PhosphorIconsStyle.regular),
                          size: 24,
                          color: colors.textSecondary,
                        ),
                      ),
                    );
                  }
                  return _WinkingEyeButton(
                    style: iconButtonStyle,
                    iconColor: colors.textSecondary,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _atPerspectivesSection.value = true;
                      final ctx = _perspectivesKey.currentContext;
                      if (ctx != null) {
                        Scrollable.ensureVisible(
                          ctx,
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeInOut,
                        );
                      } else {
                        _showPerspectives(context);
                      }
                    },
                  );
                },
              ),

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
                      size: 24,
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
                    size: 24,
                    inactiveColor: colors.textSecondary,
                  ),
                  tooltip: 'Recommander',
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
        child: child,
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
                  onPressed: () => context.pop(_content),
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
                                // Source logo (reduced from 32 to 28)
                                if (content.source.logoUrl != null)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: CachedNetworkImage(
                                      imageUrl: content.source.logoUrl!,
                                      width: 28,
                                      height: 28,
                                      fit: BoxFit.cover,
                                      errorWidget: (_, __, ___) =>
                                          _buildSourcePlaceholder(colors),
                                    ),
                                  )
                                else
                                  _buildSourcePlaceholder(colors),
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

  /// Returns individual entity chip widgets (no wrapper) for use in Wrap layouts.
  /// Tapping any chip opens the full entities sheet.
  List<Widget> _buildArticleTagWidgets(BuildContext context, Content content) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final topicsAsync = ref.watch(customTopicsProvider);
    final followedNames = (topicsAsync.valueOrNull ?? [])
        .where((t) => t.canonicalName != null)
        .map((t) => t.canonicalName!.toLowerCase())
        .toSet();

    // Dense layout: 4 tags max across macro-theme + topic + entities.
    // Remaining entities are grouped into a "+X" overflow chip.
    const maxTotalVisible = 4;

    final hasMacroTheme = content.topics.isNotEmpty &&
        getTopicMacroTheme(content.topics.first) != null;
    final hasTopic = content.topics.isNotEmpty;
    final reservedForTopics = (hasMacroTheme ? 1 : 0) + (hasTopic ? 1 : 0);
    final entities = content.entities;
    final maxEntitiesVisible =
        (maxTotalVisible - reservedForTopics).clamp(0, entities.length);
    final visible = entities.take(maxEntitiesVisible).toList();
    final overflow = entities.length - maxEntitiesVisible;

    return [
      // Macro-theme chip (thème du sujet, ex: Cinéma)
      if (hasMacroTheme)
        Builder(builder: (context) {
          final macroTheme = getTopicMacroTheme(content.topics.first)!;
          final emoji = getMacroThemeEmoji(macroTheme);
          return GestureDetector(
            onTap: () => TopicChip.showArticleSheet(context, content,
                initialSection: ArticleSheetSection.topic),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colors.textTertiary.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${emoji.isNotEmpty ? '$emoji ' : ''}$macroTheme',
                style: textTheme.labelSmall?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          );
        }),
      // Topic chip
      if (hasTopic)
        GestureDetector(
          onTap: () => TopicChip.showArticleSheet(context, content,
              initialSection: ArticleSheetSection.topic),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: colors.textTertiary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              getTopicLabel(content.topics.first),
              style: textTheme.labelSmall?.copyWith(
                color: colors.textTertiary,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      // Entity chips
      ...visible.map((entity) {
        final isFollowed = followedNames.contains(entity.text.toLowerCase());
        return GestureDetector(
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
                    style: textTheme.labelSmall?.copyWith(
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
        );
      }),
      if (overflow > 0)
        GestureDetector(
          onTap: () => TopicChip.showArticleSheet(context, content,
              initialSection: ArticleSheetSection.entities),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: colors.textTertiary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '+$overflow',
              style: textTheme.labelSmall?.copyWith(
                color: colors.textTertiary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
    ];
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

  /// Renders the sticky version of the perspectives section header (icon +
  /// title, optional quality badge, interactive bias bar).  Shown as a
  /// [Positioned] overlay below the app header when the inline section header
  /// has scrolled off-screen.
  Widget _buildPerspectivesStickyHeader(
      BuildContext context, PerspectivesResponse response) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    // Compute merged 3-group distribution from the raw bias distribution.
    final dist = response.biasDistribution;
    final merged = {
      'gauche': (dist['left'] ?? 0) + (dist['center-left'] ?? 0),
      'centre': dist['center'] ?? 0,
      'droite': (dist['center-right'] ?? 0) + (dist['right'] ?? 0),
    };

    final selected = _perspectivesSelectedSegments;

    return Container(
      decoration: BoxDecoration(
        color: colors.backgroundPrimary,
        border: Border(
          bottom: BorderSide(color: colors.border, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon + title row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                PhosphorIcons.eye(PhosphorIconsStyle.regular),
                color: colors.primary,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Voir tous les points de vue',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              // "Tout afficher" clear button when a filter is active
              if (selected.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    setState(() => _perspectivesSelectedSegments = {});
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _checkAtPerspectivesSection();
                    });
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Tout afficher',
                        style: textTheme.labelSmall?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        PhosphorIcons.x(PhosphorIconsStyle.bold),
                        size: 12,
                        color: colors.primary,
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (response.comparisonQuality == 'low')
            PerspectivesWarningBadge(colors: colors, textTheme: textTheme),
          const SizedBox(height: FacteurSpacing.space2),
          PerspectivesBiasBar(
            colors: colors,
            mergedDistribution: merged,
            sourceBiasStance: response.sourceBiasStance,
            sourceName: _content?.source.name ?? '',
            selectedSegments: selected,
            onSegmentTap: _onPerspectivesSegmentTap,
          ),
        ],
      ),
    );
  }

  Widget _buildSourcePlaceholder(FacteurColors colors) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        PhosphorIcons.newspaper(PhosphorIconsStyle.regular),
        size: 14,
        color: colors.textTertiary,
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
        // LAYER 0: WebView — fixed in viewport, always rendered.
        // Painted first so it appears visually behind the scrollable content.
        Positioned.fill(
          child: _buildWebViewLayer(),
        ),

        // LAYER 1: Scrollable article content with opaque background.
        // Container color hides WebView entirely before CTA tap;
        // becomes transparent after tap so spacer reveals WebView.
        // IgnorePointer lets touches pass through to WebView when active.
        // AnimatedOpacity hides article layer when WebView is active to prevent
        // bottom-of-article content from bleeding through the header status bar area.
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
                      // ZONE 1: Article content — opaque background hides WebView.
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
                          header: Column(
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
                              if (content.entities.isNotEmpty || isPartial) ...[
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    if (isPartial)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: colors.warning
                                              .withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(
                                              FacteurRadius.pill),
                                        ),
                                        child: Text(
                                          'Aperçu — contenu partiel',
                                          style: textTheme.labelSmall?.copyWith(
                                            color: colors.warning,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    if (content.entities.isNotEmpty)
                                      ..._buildArticleTagWidgets(
                                          context, content),
                                  ],
                                ),
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
                              Divider(color: colors.border, height: 1),
                              const SizedBox(height: FacteurSpacing.space4),
                            ],
                          ),
                          footer: SizedBox(
                              height: _kFooterContentHeight + bottomInset),
                        ),
                      ),

                      // ZONE 2: Inline perspectives (articles only)
                      if (_perspectivesResponse != null ||
                          _perspectivesLoading) ...[
                        Container(
                          color: colors.backgroundPrimary,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: FacteurSpacing.space4),
                            child: Divider(color: colors.border, height: 1),
                          ),
                        ),
                        Container(
                          color: colors.backgroundPrimary,
                          child: _perspectivesLoading &&
                                  _perspectivesResponse == null
                              ? const Center(child: CircularProgressIndicator())
                              : _perspectivesResponse != null
                                  ? PerspectivesInlineSection(
                                      key: _perspectivesKey,
                                      perspectives: _perspectivesResponse!
                                          .perspectives
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
                                      biasDistribution: _perspectivesResponse!
                                          .biasDistribution,
                                      keywords: _perspectivesResponse!.keywords,
                                      sourceBiasStance: _perspectivesResponse!
                                          .sourceBiasStance,
                                      sourceName: _content?.source.name ?? '',
                                      contentId: widget.contentId,
                                      comparisonQuality: _perspectivesResponse!
                                          .comparisonQuality,
                                      externalSelectedSegments:
                                          _perspectivesSelectedSegments,
                                      onSegmentTap: _onPerspectivesSegmentTap,
                                      onClearSegments: () {
                                        setState(() =>
                                            _perspectivesSelectedSegments = {});
                                        WidgetsBinding.instance
                                            .addPostFrameCallback((_) {
                                          if (mounted) {
                                            _checkAtPerspectivesSection();
                                          }
                                        });
                                      },
                                      analysisState: _perspectivesAnalysisState,
                                      analysisText: _perspectivesAnalysisText,
                                      onRequestAnalysis:
                                          _requestPerspectivesAnalysis,
                                      analysisZoneKey: _analysisZoneKey,
                                    )
                                  : const SizedBox.shrink(),
                        ),
                      ],

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
            // Spacer for header overlay (header sits on this, not on iframe)
            SizedBox(height: headerHeight),

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

                    // Bottom spacing for FABs
                    const SizedBox(height: _kFabBottomClearance),
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
          // Push below the header overlay
          SizedBox(height: headerHeight),

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

                  // Bottom spacing for FABs
                  const SizedBox(height: 120),
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
                      if (content.entities.isNotEmpty || isPartial)
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (isPartial)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: colors.warning.withValues(alpha: 0.12),
                                  borderRadius:
                                      BorderRadius.circular(FacteurRadius.pill),
                                ),
                                child: Text(
                                  'Aperçu — contenu partiel',
                                  style: textTheme.labelSmall?.copyWith(
                                    color: colors.warning,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            if (content.entities.isNotEmpty)
                              ..._buildArticleTagWidgets(context, content),
                          ],
                        ),
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

                const SizedBox(height: FacteurSpacing.space4),

                // ── Divider: header / article ─────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: FacteurSpacing.space4),
                  child: Divider(color: colors.border, height: 1),
                ),
                const SizedBox(height: FacteurSpacing.space4),

                // ── Article section ────────────────────────────────────────
                // Zero-height marker at the end lets _measureArticleExtent()
                // compute progress against article length only (excludes perspectives).
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    articleWidget,
                    SizedBox(key: _articleEndKey, height: 0),
                  ],
                ),

                // ── Perspectives section ───────────────────────────────────
                if (_perspectivesResponse != null || _perspectivesLoading) ...[
                  const SizedBox(height: FacteurSpacing.space4),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: FacteurSpacing.space4),
                    child: Divider(color: colors.border, height: 1),
                  ),
                  const SizedBox(height: FacteurSpacing.space4),
                  if (_perspectivesLoading && _perspectivesResponse == null)
                    const Center(child: CircularProgressIndicator())
                  else if (_perspectivesResponse != null)
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
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _checkAtPerspectivesSection();
                        });
                      },
                      analysisState: _perspectivesAnalysisState,
                      analysisText: _perspectivesAnalysisText,
                      onRequestAnalysis: _requestPerspectivesAnalysis,
                      analysisZoneKey: _analysisZoneKey,
                    ),
                ],

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
        return Column(
          children: [
            SizedBox(height: headerHeight),
            Expanded(
              child: AudioPlayerWidget(
                audioUrl: content.audioUrl!,
                title: content.title,
                description: content.description,
                thumbnailUrl: content.thumbnailUrl,
                durationSeconds: content.durationSeconds,
              ),
            ),
          ],
        );

      case ContentType.youtube:
      case ContentType.video:
        return Column(
          children: [
            SizedBox(height: headerHeight),
            Expanded(
              child: YouTubePlayerWidget(
                videoUrl: content.url,
                title: content.title,
                description: content.description,
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
        SizedBox(height: headerHeight),
        // Extra breathing room so tag chips aren't clipped by the header overlay
        const SizedBox(height: FacteurSpacing.space2),
        if (content.entities.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: FacteurSpacing.space4,
              vertical: 6,
            ),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: _buildArticleTagWidgets(context, content),
            ),
          ),
        Expanded(child: WebViewWidget(controller: _webViewController!)),
      ],
    );
  }
}

/// Eye button that winks periodically (scaleY close → open) to hint at perspectives.
class _WinkingEyeButton extends StatefulWidget {
  final VoidCallback onTap;
  final ButtonStyle? style;
  final Color iconColor;

  const _WinkingEyeButton({
    required this.onTap,
    this.style,
    required this.iconColor,
  });

  @override
  State<_WinkingEyeButton> createState() => _WinkingEyeButtonState();
}

class _WinkingEyeButtonState extends State<_WinkingEyeButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleY;
  final math.Random _rng = math.Random();
  final Stopwatch _timeOnScreen = Stopwatch();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timeOnScreen.start();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _scaleY = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.05)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 30, // close fast (~96ms)
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.05, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 70, // open slower (~224ms)
      ),
    ]).animate(_controller);
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) _scheduleNext();
    });
    _scheduleNext();
  }

  void _scheduleNext() {
    final elapsed = _timeOnScreen.elapsed.inSeconds;
    // Multiplier grows from 1× at t=0 to 3× at t=60s, then stays at 3×.
    final multiplier = (3.0 * (elapsed.clamp(0, 60) / 60.0)).clamp(1.0, 3.0);
    final baseMs = 2000 + _rng.nextInt(3001); // 2–5 s
    final delayMs = (baseMs * multiplier).round();
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
      animation: _scaleY,
      builder: (context, _) {
        final isWinking = _scaleY.value < 0.5;
        return IconButton(
          style: widget.style,
          onPressed: widget.onTap,
          tooltip: 'Autres points de vue',
          icon: Transform.scale(
            scaleY: _scaleY.value,
            child: Icon(
              isWinking
                  ? PhosphorIcons.eyeClosed(PhosphorIconsStyle.regular)
                  : PhosphorIcons.eye(PhosphorIconsStyle.regular),
              size: 22,
              color: widget.iconColor,
            ),
          ),
        );
      },
    );
  }
}

/// Subtle periodic nudge on the source badge to hint at long-press.
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
