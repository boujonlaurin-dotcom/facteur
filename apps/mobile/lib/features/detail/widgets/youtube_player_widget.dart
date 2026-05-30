import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/constants.dart';
import '../../../config/theme.dart';

/// YouTube video player widget (Story 5.2)
///
/// Loads the YouTube IFrame Player API via a wrapper page served from our own
/// backend (`/api/youtube/player?v=...`). Serving the wrapper from a real
/// https origin gives the embedded YouTube iframe a valid Referer/Origin —
/// the canonical fix for Android WebView Error 153. (Loading the embed
/// directly, or via `loadDataWithBaseURL`, fails because Android WebView
/// doesn't attach an Origin/Referer in those cases, so YouTube refuses the
/// embed. This mirrors what the old corsproxy.io wrapper did, but self-hosted.)
///
/// A standard Chrome mobile User-Agent is also set (no "wv" marker) as
/// defense in depth. The YT.Player JS API drives progress, play state, and
/// playbackRate (long-press 2x). Falls back to "open in YouTube" on error.
class YouTubePlayerWidget extends StatefulWidget {
  final String videoUrl;
  final String title;
  final String? description;
  final Widget? footer;
  final double aspectRatio;
  final ValueChanged<double>? onProgressChanged; // 0.0 to 1.0
  final ValueChanged<bool>? onPlayStateChanged; // true = playing

  const YouTubePlayerWidget({
    super.key,
    required this.videoUrl,
    required this.title,
    this.description,
    this.footer,
    this.aspectRatio = 16 / 9,
    this.onProgressChanged,
    this.onPlayStateChanged,
  });

  @override
  State<YouTubePlayerWidget> createState() => _YouTubePlayerWidgetState();
}

class _YouTubePlayerWidgetState extends State<YouTubePlayerWidget> {
  /// Host of our backend origin — whitelisted in [shouldOverrideUrlLoading].
  /// Derived once from the (constant) [ApiConstants.baseUrl].
  static final String _apiHost = WebUri(ApiConstants.baseUrl).host;

  InAppWebViewController? _controller;
  String? _videoId;
  double _lastReportedProgress = -1.0;
  bool _isSpeedBoosted = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _videoId = _extractVideoId(widget.videoUrl);
  }

  @override
  void dispose() {
    // Restore portrait lock in case widget is disposed while in fullscreen.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  /// Extract YouTube video ID from various URL formats.
  static String? _extractVideoId(String url) {
    final watchMatch = RegExp(r'[?&]v=([a-zA-Z0-9_-]{11})').firstMatch(url);
    if (watchMatch != null) return watchMatch.group(1);

    final pathMatch =
        RegExp(r'(?:youtu\.be|youtube\.com/(?:embed|shorts))/([a-zA-Z0-9_-]{11})')
            .firstMatch(url);
    if (pathMatch != null) return pathMatch.group(1);

    final vMatch =
        RegExp(r'youtube\.com/v/([a-zA-Z0-9_-]{11})').firstMatch(url);
    if (vMatch != null) return vMatch.group(1);

    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(url)) return url;

    return null;
  }

  /// URL of the backend-hosted IFrame Player wrapper page for [videoId].
  /// Served from our real https origin so the YouTube embed gets a valid
  /// Referer (bypasses Error 153). [ApiConstants.baseUrl] ends with `/`.
  String _playerUrl(String videoId) =>
      '${ApiConstants.baseUrl}youtube/player?v=$videoId';

  void _startSpeedBoost() {
    setState(() => _isSpeedBoosted = true);
    _controller?.evaluateJavascript(
      source: 'if(window.setPlaybackRate) window.setPlaybackRate(2.0)',
    );
  }

  void _stopSpeedBoost() {
    setState(() => _isSpeedBoosted = false);
    _controller?.evaluateJavascript(
      source: 'if(window.setPlaybackRate) window.setPlaybackRate(1.0)',
    );
  }

  void _openInYouTube() {
    final url = 'https://www.youtube.com/watch?v=$_videoId';
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    if (_videoId == null) {
      return _buildErrorState(
        colors,
        textTheme,
        'Impossible de charger la vidéo YouTube',
      );
    }

    if (_hasError) {
      return _buildErrorState(
        colors,
        textTheme,
        'Vidéo indisponible dans l\'app',
      );
    }

    final settings = InAppWebViewSettings(
      javaScriptEnabled: true,
      mediaPlaybackRequiresUserGesture: false,
      allowsInlineMediaPlayback: true,
      transparentBackground: true,
      // Chrome mobile UA (no "wv" marker) so YouTube doesn't block via
      // WebView detection (Error 153 / 152-4).
      userAgent:
          'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
    );

    final playerWidget = InAppWebView(
      // Wrapper page served from our backend origin → the YouTube embed
      // iframe gets a valid Referer → no Error 153.
      initialUrlRequest: URLRequest(url: WebUri(_playerUrl(_videoId!))),
      initialSettings: settings,
      onWebViewCreated: (controller) {
        _controller = controller;

        controller.addJavaScriptHandler(
          handlerName: 'FlutterProgress',
          callback: (args) {
            if (widget.onProgressChanged == null) return;
            final progress = (args.isNotEmpty ? args[0] as num? : null)
                    ?.toDouble() ??
                0.0;
            if ((progress - _lastReportedProgress).abs() >= 0.02) {
              _lastReportedProgress = progress;
              widget.onProgressChanged!(progress);
            }
          },
        );

        controller.addJavaScriptHandler(
          handlerName: 'FlutterPlayState',
          callback: (args) {
            final isPlaying =
                args.isNotEmpty && (args[0] as num?)?.toInt() == 1;
            widget.onPlayStateChanged?.call(isPlaying);
          },
        );

        controller.addJavaScriptHandler(
          handlerName: 'FlutterError',
          callback: (args) {
            if (mounted) setState(() => _hasError = true);
          },
        );
      },
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame ?? false) {
          if (mounted) setState(() => _hasError = true);
        }
      },
      onEnterFullscreen: (controller) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      },
      onExitFullscreen: (controller) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.edgeToEdge,
          overlays: SystemUiOverlay.values,
        );
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final uri = navigationAction.request.url;
        if (uri == null) return NavigationActionPolicy.CANCEL;
        final host = uri.host;
        if (host == _apiHost ||
            host.endsWith('youtube.com') ||
            host.endsWith('youtube-nocookie.com') ||
            host.endsWith('ytimg.com') ||
            host.endsWith('googlevideo.com') ||
            host.endsWith('google.com') ||
            host.endsWith('gstatic.com')) {
          return NavigationActionPolicy.ALLOW;
        }
        return NavigationActionPolicy.CANCEL;
      },
    );

    final sizedPlayer = AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: playerWidget,
    );

    final playerWithSpeedBoost = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPressStart: (_) => _startSpeedBoost(),
      onLongPressEnd: (_) => _stopSpeedBoost(),
      child: Stack(
        children: [
          sizedPlayer,
          if (_isSpeedBoosted)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.fast_forward,
                      size: 14,
                      color: Colors.white.withOpacity(0.9),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '2x',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );

    if (widget.aspectRatio < 1.0 &&
        widget.description == null &&
        widget.footer == null) {
      return playerWithSpeedBoost;
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          playerWithSpeedBoost,
          if (widget.description != null && widget.description!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(FacteurSpacing.space4),
              child: Text(
                widget.description!,
                style: textTheme.bodyLarge?.copyWith(
                  color: colors.textSecondary,
                  height: 1.6,
                ),
              ),
            ),
          if (widget.footer != null) ...[
            const SizedBox(height: FacteurSpacing.space8),
            widget.footer!,
            const SizedBox(height: FacteurSpacing.space16),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorState(
    FacteurColors colors,
    TextTheme textTheme,
    String message,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FacteurSpacing.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.play_circle_outline,
              size: 48,
              color: colors.textSecondary,
            ),
            const SizedBox(height: FacteurSpacing.space4),
            Text(
              message,
              style:
                  textTheme.bodyLarge?.copyWith(color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
            if (_videoId != null) ...[
              const SizedBox(height: FacteurSpacing.space4),
              TextButton.icon(
                onPressed: _openInYouTube,
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Regarder sur YouTube'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
