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
import '../../digest/widgets/article_thumbs_feedback.dart';
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
const double _kHeaderContentHeight = 50;

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
  bool _showNoteWelcome = false;
  bool _linkCopiedFab = false;
  bool _linkCopiedHeader = false;
  Timer? _linkCopiedFabTimer;
  Timer? _linkCopiedHeaderTimer;
  bool _premiumRedirectScheduled = false;
  bool _webFallbackRedirectScheduled = false;
  late DateTime _startTime;
  WebViewController? _webViewController;
  bool _showWebView = false;

  // Scroll-to-site state
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _articleKey = GlobalKey();
  final GlobalKey _bridgeKey = GlobalKey();
  bool _isWebViewActive = false;
  bool _ctaTapped = false;
  double _bridgeStartOffset = 0;
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
  double _prevNativeScrollOffset = 0.0;
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

  // Video detail screen state
  bool _isDescriptionExpanded = false;
  bool _isVideoPlaying = false;
  Timer? _videoPlayHideTimer;

  Content? _content;
  bool _contentResolved = false;

  // Perspectives pill state
  PerspectivesResponse? _perspectivesResponse;
  bool _perspectivesLoading = false;

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

    // Header hide/show: track scroll delta for native in-app content
    _scrollController.addListener(_onNativeScrollHeader);

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
    final rawProgress = _scrollController.offset / maxExtent;
    // Partial content: in-app scroll represents only ~25% of the full article
    final progress = _isPartialContent
        ? (rawProgress * 0.25).clamp(0.0, 0.25)
        : rawProgress.clamp(0.0, 1.0);
    _readingProgress.value = progress;
    if (progress > _maxReadingProgress) {
      _maxReadingProgress = progress;
    }
  }

  /// Show header when user reaches the bottom of the article (progress ≥ 98%).
  void _onReadingProgressNudge() {
    if (_readingProgress.value >= 0.98 && _headerOffset.value > 0.0) {
      _inactivityTimer?.cancel();
      _animateHeaderTo(0.0);
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
    }
  }

  /// Compute layout offsets for bridge zone.
  /// Re-measures on every call to handle late HTML rendering (images, etc).
  void _computeScrollOffsets() {
    final articleBox =
        _articleKey.currentContext?.findRenderObject() as RenderBox?;
    final bridgeBox =
        _bridgeKey.currentContext?.findRenderObject() as RenderBox?;

    if (articleBox == null || bridgeBox == null) return;

    final articleHeight = articleBox.size.height;
    final bridgeHeight = bridgeBox.size.height;

    // Update offsets if article height changed (handles late HTML rendering)
    if ((articleHeight - _bridgeStartOffset).abs() > 1.0) {
      _bridgeStartOffset = articleHeight;
      _bridgeEndOffset = articleHeight + bridgeHeight;
    }

    _offsetsComputed = true;
  }

  /// Scroll listener driving WebView activation.
  void _onScrollToSite() {
    if (!_ctaTapped || !_offsetsComputed) return;

    // Re-measure on every scroll to handle late HTML rendering
    _computeScrollOffsets();

    final offset = _scrollController.offset;
    final shouldActivate = offset >= _bridgeEndOffset;

    if (shouldActivate != _isWebViewActive) {
      setState(() {
        _isWebViewActive = shouldActivate;
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

  /// Scroll listener for native (in-app) content — computes delta from previous
  /// offset and forwards it to [_onScrollDelta].
  void _onNativeScrollHeader() {
    if (!_scrollController.hasClients || _isWebViewActive) return;
    final current = _scrollController.offset;
    final delta = current - _prevNativeScrollOffset;
    _prevNativeScrollOffset = current;
    if (delta != 0) _onScrollDelta(delta);
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
    }
    // FABs reappear after 2.5s
    _scrollStopTimer?.cancel();
    _scrollStopTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) {
        _fabOpacity.value = 1.0;
        _fabReappearController.forward(from: 0);
      }
    });
    // Auto-hide header after 3s of inactivity (no scroll), but only if not at top
    _inactivityTimer?.cancel();
    if (!isVideo && !_isShortArticle) {
      _inactivityTimer = Timer(const Duration(seconds: 3), () {
        final nativeScrollY =
            _scrollController.hasClients ? _scrollController.offset : 0.0;
        final scrolledPastTop = _webScrollY > 0 || nativeScrollY > 0;
        if (mounted && scrolledPastTop && _headerOffset.value < 1.0) {
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
            description: _pickLongest(content.description, _content?.description),
            htmlContent: _pickLongest(content.htmlContent, _content?.htmlContent),
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
          // Re-check short article after content loads and renders
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _checkShortArticle();
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
          // Content not found via API. Keep whatever was passed via extra
          // (e.g. a digest "Pas de recul" article whose row was just culled
          // server-side) so the screen still renders instead of bouncing
          // the user back to the previous screen with a blank flash.
          setState(() => _contentResolved = true);
          if (_content == null) {
            NotificationService.showError('Contenu introuvable',
                context: context);
            context.pop();
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching content: $e');
      if (mounted) {
        setState(() => _contentResolved = true);
        // Same fallback: only pop when we truly have nothing to show.
        if (_content == null) {
          NotificationService.showError('Erreur de chargement',
              context: context);
          context.pop();
        }
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
              ? 'Ajouté à Mes articles intéressants 🌻'
              : 'Retiré de Mes articles intéressants 🌻',
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
    WidgetsBinding.instance.removeObserver(this);
    _fabOpacity.dispose();
    _headerOffset.dispose();
    _readingProgress.removeListener(_onReadingProgressNudge);
    _readingProgress.removeListener(_onShareFabProgress);
    _readingProgress.dispose();
    _scrollController.removeListener(_onScrollToSite);
    _scrollController.removeListener(_onScrollReadingProgress);

    _scrollController.dispose();
    super.dispose();

    // Persist reading progress + analytics on close
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
              SizedBox(height: 16),
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
        initialAnalysis: response.analysis,
        analysisCached: response.analysisCached,
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
              const SizedBox(height: 16),
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
              const SizedBox(height: 16),
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
                  _headerOffset.value = 0.0;
                }
                _onScrollDelta(delta);
                // Track reading progress from any scrollable (including in-app reader)
                final metrics = notification.metrics;
                if (metrics.maxScrollExtent > 0) {
                  final progress = metrics.pixels / metrics.maxScrollExtent;
                  final capped = _isPartialContent
                      ? (progress * 0.25).clamp(0.0, 0.25)
                      : progress.clamp(0.0, 1.0);
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
                final headerHeight =
                    MediaQuery.of(context).padding.top + _kHeaderContentHeight;
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
        ],
      ),
      ),
      // FABs — vertical column with immersive scroll opacity
      // ValueListenableBuilder isolates FAB opacity rebuilds from the main widget tree.
      floatingActionButton: _showFab
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
                          const SizedBox(height: 12),
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
                              _showPerspectives(context);
                            },
                          ),
                          const SizedBox(height: 12),
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
                          const SizedBox(height: 12),
                        ],
                        // 🌻 Sunflower recommendation FAB + nudge label
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Animated "Recommander ?" nudge label
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0.3, 0),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                              child: _showSunflowerNudge
                                  ? Container(
                                      key: const ValueKey('nudge_visible'),
                                      margin: const EdgeInsets.only(right: 10),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFF8E1),
                                        borderRadius:
                                            BorderRadius.circular(16),
                                        boxShadow: [
                                          BoxShadow(
                                            color:
                                                Colors.black.withValues(alpha: 0.1),
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
                            ScaleTransition(
                              scale: _likeScaleAnimation,
                              child: SizedBox(
                                width: 50,
                                height: 50,
                                child: FloatingActionButton(
                                  onPressed: _toggleLike,
                                  backgroundColor: Colors.white,
                                  foregroundColor: colors.textPrimary,
                                  elevation: 2,
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
                          ],
                        ),
                        const SizedBox(height: 12),
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
                          const SizedBox(height: 12),
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

  Widget _buildHeader(BuildContext context, Content content) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    // ColoredBox fills the status bar area; SafeArea pushes content below it
    final headerContent = ColoredBox(
      color: colors.backgroundPrimary,
      child: SafeArea(
        bottom: false,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: FacteurSpacing.space2,
            vertical: FacteurSpacing.space2,
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
                            ref.read(feedProvider.notifier).setSource(content.source.id);
                            ref.read(feedScrollTriggerProvider.notifier).state++;
                            context.pop(_content);
                          },
                          onLongPress: () => TopicChip.showArticleSheet(
                            context, content,
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Ligne 1 : Nom (mini-chip) + Badges
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Opacity(
                                            opacity: 0.9,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Color.lerp(colors.backgroundSecondary, Colors.black, 0.003)!,
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                content.source.name,
                                                style: textTheme.labelMedium?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                  color: colors.textPrimary,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ),
                                        ),
                                        // Bias dot
                                        if (content.source.biasStance != 'unknown') ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            width: 7,
                                            height: 7,
                                            decoration: BoxDecoration(
                                              color: content.source.getBiasColor(),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        ],
                                        // Gear icon — same scale as bias dot
                                        const SizedBox(width: 4),
                                        Material(
                                          color: Colors.transparent,
                                          shape: const CircleBorder(),
                                          clipBehavior: Clip.antiAlias,
                                          child: InkWell(
                                            onTap: () => TopicChip.showArticleSheet(
                                              context, content,
                                              initialSection: ArticleSheetSection.source,
                                            ),
                                            child: Padding(
                                              padding: const EdgeInsets.all(3),
                                              child: Icon(
                                                PhosphorIcons.gear(PhosphorIconsStyle.regular),
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
                                          PhosphorIcons.clock(PhosphorIconsStyle.regular),
                                          size: 11,
                                          color: colors.textTertiary,
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          timeago
                                              .format(content.publishedAt, locale: 'fr_short')
                                              .replaceAll('il y a ', ''),
                                          style: textTheme.bodySmall?.copyWith(
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
    const chipPadding = EdgeInsets.symmetric(horizontal: 7, vertical: 3);

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
            onTap: () => TopicChip.showArticleSheet(context, content, initialSection: ArticleSheetSection.topic),
            child: Container(
              padding: chipPadding,
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
          onTap: () => TopicChip.showArticleSheet(context, content, initialSection: ArticleSheetSection.topic),
          child: Container(
            padding: chipPadding,
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
        final isFollowed =
            followedNames.contains(entity.text.toLowerCase());
        return GestureDetector(
          onTap: () => TopicChip.showArticleSheet(context, content, initialSection: ArticleSheetSection.entities),
          child: Container(
            padding: chipPadding,
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
                  constraints: const BoxConstraints(maxWidth: 90),
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
          onTap: () => TopicChip.showArticleSheet(context, content, initialSection: ArticleSheetSection.entities),
          child: Container(
            padding: chipPadding,
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
        const SizedBox(height: 16),
        for (final w in widths)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
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
                color: _ctaTapped
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
                      // ZONE 1: Article content — opaque background hides WebView
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
                              // Extra breathing room so tag chips aren't clipped by the header overlay
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
                              // Entity chips + partial badge row
                              if (content.entities.isNotEmpty ||
                                  isPartial) ...[
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    if (isPartial)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: colors.warning
                                              .withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(
                                              FacteurRadius.pill),
                                        ),
                                        child: Text(
                                          'Aperçu — contenu partiel',
                                          style:
                                              textTheme.labelSmall?.copyWith(
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
                              // Editorial badge above title (from digest)
                              if (content.editorialBadge != null) ...[
                                EditorialBadge.chip(
                                  content.editorialBadge,
                                  context: context,
                                ) ?? const SizedBox.shrink(),
                                const SizedBox(height: FacteurSpacing.space2),
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
                                        color: colors.textTertiary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: FacteurSpacing.space3),
                              ],
                              Divider(color: colors.border, height: 1),
                              const SizedBox(height: FacteurSpacing.space4),
                            ],
                          ),
                        ),
                      ),

                      // Article feedback thumbs
                      Container(
                        color: colors.backgroundPrimary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: FacteurSpacing.space4,
                        ),
                        child: ArticleThumbsFeedback(contentId: content.id),
                      ),

                      // ZONE 2: CTA button — intentional transition to WebView
                      Container(
                        color: colors.backgroundPrimary,
                        child: Padding(
                          key: _bridgeKey,
                          padding: EdgeInsets.only(
                            left: FacteurSpacing.space4,
                            right: FacteurSpacing.space4,
                            top: FacteurSpacing.space3,
                            bottom: FacteurSpacing.space3 + bottomInset,
                          ),
                          child: GestureDetector(
                            onTap: () {
                              if (_offsetsComputed && !_ctaTapped) {
                                setState(() {
                                  _ctaTapped = true;
                                });
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  if (mounted) {
                                    _scrollController.animateTo(
                                      _scrollController
                                          .position.maxScrollExtent,
                                      duration:
                                          const Duration(milliseconds: 500),
                                      curve: Curves.easeInOutCubic,
                                    );
                                  }
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 16,
                              ),
                              decoration: BoxDecoration(
                                color: colors.surfaceElevated,
                                borderRadius:
                                    BorderRadius.circular(FacteurRadius.large),
                                border: Border.all(
                                  color: colors.border.withValues(alpha: 0.5),
                                ),
                              ),
                              child: Row(
                                children: [
                                  if (content.source.logoUrl != null)
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: CachedNetworkImage(
                                        imageUrl: content.source.logoUrl!,
                                        width: 28,
                                        height: 28,
                                        fit: BoxFit.cover,
                                        errorWidget: (_, __, ___) => Container(
                                          width: 28,
                                          height: 28,
                                          decoration: BoxDecoration(
                                            color: colors.surface,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Icon(
                                            PhosphorIcons.newspaper(
                                                PhosphorIconsStyle.regular),
                                            size: 16,
                                            color: colors.textTertiary,
                                          ),
                                        ),
                                      ),
                                    )
                                  else
                                    Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        color: colors.surface,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        PhosphorIcons.newspaper(
                                            PhosphorIconsStyle.regular),
                                        size: 16,
                                        color: colors.textTertiary,
                                      ),
                                    ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Lire sur ${content.source.name}',
                                      style: textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: colors.textPrimary,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    PhosphorIcons.arrowRight(
                                        PhosphorIconsStyle.regular),
                                    size: 20,
                                    color: colors.textTertiary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                      // ZONE 3: Transparent spacer — only after CTA tap to enable scroll animation
                      if (_ctaTapped) SizedBox(height: availableHeight),
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
    final descriptionText = rawDescription != null
        ? stripHtml(rawDescription).trim()
        : null;

    return LayoutBuilder(builder: (context, constraints) {
      final maxHeight = constraints.maxHeight;

      // --- Shorts: Column layout (no overlay on iframe → all buttons clickable) ---
      if (isShort) {
        // Reserve ~160px below the player for metadata (scrollable, same
        // pattern as regular videos). FABs float over this Flutter text area
        // (not an iframe) so they remain clickable.
        final shortsPlayerHeight = (maxHeight - headerHeight - 140)
            .clamp(200.0, screenWidth * 16 / 9);

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
                          setState(() => _isDescriptionExpanded =
                              !_isDescriptionExpanded);
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
                        backgroundImage:
                            CachedNetworkImageProvider(content.source.logoUrl!),
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
                      setState(
                          () => _isDescriptionExpanded = !_isDescriptionExpanded);
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

        return ArticleReaderWidget(
          htmlContent: content.htmlContent,
          description: content.description,
          title: content.title,
          onLinkTap: _animateAndLaunch,
          bodyPlaceholder: !_contentResolved
              ? _buildArticleBodySkeleton(colors)
              : null,
          header: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Spacer: scrolls with content, initially behind the header overlay
              SizedBox(height: headerHeight),
              // Extra breathing room so tag chips aren't clipped by the header overlay
              const SizedBox(height: FacteurSpacing.space2),
              // Hero thumbnail image (smooth integration)
              if (content.thumbnailUrl != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(FacteurRadius.large),
                  child: FacteurThumbnail(
                    imageUrl: content.thumbnailUrl,
                    aspectRatio: 16 / 9,
                  ),
                ),
                const SizedBox(height: FacteurSpacing.space3),
              ],
              // Entity chips + partial badge row
              if (content.entities.isNotEmpty || isPartial) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (isPartial)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
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
                const SizedBox(height: FacteurSpacing.space4),
              ],
              // Editorial badge above title (from digest)
              if (content.editorialBadge != null) ...[
                EditorialBadge.chip(
                  content.editorialBadge,
                  context: context,
                ) ?? const SizedBox.shrink(),
                const SizedBox(height: FacteurSpacing.space2),
              ],
              // Title
              Text(
                content.title,
                style: textTheme.displayLarge?.copyWith(fontSize: 24),
              ),
              const SizedBox(height: FacteurSpacing.space2),
              // Reading time
              if (readingTime != null) ...[
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
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: FacteurSpacing.space3),
              ],
              Divider(color: colors.border, height: 1),
              const SizedBox(height: FacteurSpacing.space4),
            ],
          ),
          footer: GestureDetector(
            onTap: kIsWeb
                ? _openOriginalUrl
                : () => setState(() => _showWebView = true),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 16,
              ),
              decoration: BoxDecoration(
                color: colors.surfaceElevated,
                borderRadius: BorderRadius.circular(FacteurRadius.large),
                border: Border.all(
                  color: colors.border.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  if (content.source.logoUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: content.source.logoUrl!,
                        width: 28,
                        height: 28,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            PhosphorIcons.newspaper(PhosphorIconsStyle.regular),
                            size: 16,
                            color: colors.textTertiary,
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        PhosphorIcons.newspaper(PhosphorIconsStyle.regular),
                        size: 16,
                        color: colors.textTertiary,
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Lire sur ${content.source.name}',
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  Icon(
                    PhosphorIcons.arrowRight(PhosphorIconsStyle.regular),
                    size: 20,
                    color: colors.textTertiary,
                  ),
                ],
              ),
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
        Expanded(child: WebViewWidget(controller: _webViewController!)),
      ],
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
