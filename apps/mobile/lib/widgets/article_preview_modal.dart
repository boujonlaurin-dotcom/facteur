import 'package:cached_network_image/cached_network_image.dart';
import 'package:facteur/config/theme.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

/// Overlay-based floating preview, shown on long-press start,
/// dismissed on long-press end. Supports scroll via finger drag.
class ArticlePreviewOverlay {
  static OverlayEntry? _overlayEntry;
  static _ArticlePreviewWidgetState? _currentState;
  static bool _isDismissing = false;

  /// Show the preview overlay for the given content.
  static void show(BuildContext context, Content content) {
    if (_overlayEntry != null) {
      if (_isDismissing) {
        // Fast-cancel exit animation, remove immediately, then re-show
        _currentState?._animController.stop();
        _overlayEntry?.remove();
        _overlayEntry = null;
        _currentState = null;
        _isDismissing = false;
      } else {
        return; // Already showing
      }
    }

    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(
      builder: (context) => _ArticlePreviewWidget(
        content: content,
        onStateReady: (state) => _currentState = state,
      ),
    );
    overlay.insert(_overlayEntry!);
  }

  /// Update the scroll position of the description area.
  /// [cumulativeDeltaY] is from LongPressMoveUpdateDetails.localOffsetFromOrigin.dy.
  static void updateScroll(double cumulativeDeltaY) {
    _currentState?.scrollBy(cumulativeDeltaY);
  }

  /// Dismiss the preview overlay with reverse animation.
  static void dismiss() {
    if (_currentState == null || _isDismissing) return;
    _isDismissing = true;
    _currentState!._exit(() {
      _overlayEntry?.remove();
      _overlayEntry = null;
      _currentState = null;
      _isDismissing = false;
    });
  }
}

class _ArticlePreviewWidget extends StatefulWidget {
  final Content content;
  final ValueChanged<_ArticlePreviewWidgetState> onStateReady;

  const _ArticlePreviewWidget({
    required this.content,
    required this.onStateReady,
  });

  @override
  State<_ArticlePreviewWidget> createState() => _ArticlePreviewWidgetState();
}

class _ArticlePreviewWidgetState extends State<_ArticlePreviewWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _curvedAnimation;
  final ScrollController _scrollController = ScrollController();
  double _lastDeltaY = 0.0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: FacteurDurations.fast,
    );
    _curvedAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    widget.onStateReady(this);
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _scrollController.dispose();
    // Clean up statics if we're disposed externally (e.g. navigation)
    if (ArticlePreviewOverlay._currentState == this) {
      ArticlePreviewOverlay._overlayEntry = null;
      ArticlePreviewOverlay._currentState = null;
      ArticlePreviewOverlay._isDismissing = false;
    }
    super.dispose();
  }

  void scrollBy(double cumulativeDeltaY) {
    if (!_scrollController.hasClients) return;
    final incrementalDelta = cumulativeDeltaY - _lastDeltaY;
    _lastDeltaY = cumulativeDeltaY;
    final newOffset = (_scrollController.offset - incrementalDelta)
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.jumpTo(newOffset);
  }

  void _exit(VoidCallback onComplete) {
    _animController.reverse().then((_) => onComplete());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final screenSize = MediaQuery.of(context).size;
    final content = widget.content;

    // Listener catches PointerUp independently of the gesture arena,
    // guaranteeing dismissal even if the GestureDetector loses track
    // (e.g. widget rebuild during long-press in a CustomScrollView).
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerUp: (_) => ArticlePreviewOverlay.dismiss(),
      onPointerCancel: (_) => ArticlePreviewOverlay.dismiss(),
      child: AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        return Stack(
          children: [
            // Barrier — non-interactive, reduced opacity
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color:
                      Colors.black.withValues(alpha: 0.3 * _curvedAnimation.value),
                ),
              ),
            ),
            // Preview card
            Center(
              child: FadeTransition(
                opacity: _curvedAnimation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.85, end: 1.0)
                      .animate(_curvedAnimation),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: screenSize.width,
                      maxHeight: screenSize.height * 0.85,
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: Container(
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius:
                              BorderRadius.circular(FacteurRadius.large),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius:
                              BorderRadius.circular(FacteurRadius.large),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Thumbnail (fixed, not scrollable)
                              if (content.thumbnailUrl != null &&
                                  content.thumbnailUrl!.isNotEmpty)
                                AspectRatio(
                                  aspectRatio: 16 / 9,
                                  child: CachedNetworkImage(
                                    imageUrl: content.thumbnailUrl!,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => Container(
                                      color: colors.backgroundSecondary,
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: colors.primary
                                              .withValues(alpha: 0.5),
                                        ),
                                      ),
                                    ),
                                    errorWidget: (context, url, error) =>
                                        Container(
                                      color: colors.backgroundSecondary,
                                      child: Icon(
                                        PhosphorIcons.imageBroken(
                                            PhosphorIconsStyle.duotone),
                                        color: colors.textSecondary,
                                        size: 32,
                                      ),
                                    ),
                                  ),
                                ),

                              // Scrollable content area
                              Flexible(
                                child: SingleChildScrollView(
                                  controller: _scrollController,
                                  physics:
                                      const NeverScrollableScrollPhysics(),
                                  child: Padding(
                                    padding: const EdgeInsets.all(
                                        FacteurSpacing.space4),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Source row
                                        Row(
                                          children: [
                                            if (content.source.logoUrl !=
                                                    null &&
                                                content.source.logoUrl!
                                                    .isNotEmpty) ...[
                                              ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                child: CachedNetworkImage(
                                                  imageUrl:
                                                      content.source.logoUrl!,
                                                  width: 20,
                                                  height: 20,
                                                  fit: BoxFit.cover,
                                                  errorWidget:
                                                      (context, url, error) =>
                                                          _buildSourcePlaceholder(
                                                              colors,
                                                              content),
                                                ),
                                              ),
                                              const SizedBox(
                                                  width:
                                                      FacteurSpacing.space2),
                                            ] else ...[
                                              _buildSourcePlaceholder(
                                                  colors, content),
                                              const SizedBox(
                                                  width:
                                                      FacteurSpacing.space2),
                                            ],
                                            Flexible(
                                              child: Text(
                                                content.source.name,
                                                style: textTheme.labelMedium
                                                    ?.copyWith(
                                                  color: colors.textPrimary,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(
                                                width:
                                                    FacteurSpacing.space2),
                                            Text(
                                              timeago
                                                  .format(
                                                      content.publishedAt,
                                                      locale: 'fr_short')
                                                  .replaceAll('il y a ', ''),
                                              style: textTheme.labelSmall
                                                  ?.copyWith(
                                                color: colors.textSecondary,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),

                                        const SizedBox(
                                            height: FacteurSpacing.space3),

                                        // Title
                                        Text(
                                          content.title,
                                          style: textTheme.displaySmall
                                              ?.copyWith(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w700,
                                            height: 1.2,
                                          ),
                                          maxLines: 6,
                                          overflow: TextOverflow.ellipsis,
                                        ),

                                        // Description (no maxLines — scrollable, HTML stripped)
                                        if (content.description != null &&
                                            content
                                                .description!.isNotEmpty) ...[
                                          const SizedBox(
                                              height: FacteurSpacing.space3),
                                          Text(
                                            _stripHtml(content.description!),
                                            style: textTheme.bodyMedium
                                                ?.copyWith(
                                              color: colors.textPrimary
                                                  .withValues(alpha: 0.85),
                                              height: 1.5,
                                              fontSize: 14.5,
                                            ),
                                          ),
                                        ],

                                        const SizedBox(
                                            height: FacteurSpacing.space3),

                                        // Metadata row
                                        Row(
                                          children: [
                                            _buildTypeIcon(
                                                context,
                                                content.contentType),
                                            if (content.durationSeconds !=
                                                null) ...[
                                              const SizedBox(
                                                  width:
                                                      FacteurSpacing.space2),
                                              Text(
                                                _formatDuration(
                                                    content.durationSeconds!),
                                                style: textTheme.labelSmall
                                                    ?.copyWith(
                                                  color:
                                                      colors.textSecondary,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),

                                        const SizedBox(
                                            height: FacteurSpacing.space3),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
    );
  }

  Widget _buildSourcePlaceholder(FacteurColors colors, Content content) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Text(
          content.source.name.isNotEmpty
              ? content.source.name.substring(0, 1).toUpperCase()
              : '?',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: colors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildTypeIcon(BuildContext context, ContentType type) {
    final colors = context.facteurColors;
    IconData icon;

    switch (type) {
      case ContentType.video:
      case ContentType.youtube:
        icon = PhosphorIcons.filmStrip(PhosphorIconsStyle.fill);
        break;
      case ContentType.audio:
        icon = PhosphorIcons.headphones(PhosphorIconsStyle.fill);
        break;
      default:
        return const SizedBox.shrink();
    }

    return Icon(icon, size: 14, color: colors.textSecondary);
  }

  static String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final minutes = (seconds / 60).ceil();
    return '$minutes min';
  }

  /// Strip HTML tags and decode common entities from RSS descriptions.
  static String _stripHtml(String html) {
    // Remove HTML tags
    var text = html.replaceAll(RegExp(r'<[^>]+>'), '');
    // Decode common HTML entities
    text = text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&#8217;', '\u2019')
        .replaceAll('&#8216;', '\u2018')
        .replaceAll('&#8220;', '\u201C')
        .replaceAll('&#8221;', '\u201D');
    // Collapse multiple whitespace/newlines into single space
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text;
  }
}
