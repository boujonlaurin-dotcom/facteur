import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../../../config/theme.dart';

/// YouTube video player widget (Story 5.2)
/// Uses webview_flutter directly with baseUrl to ensure proper HTTP Referer
/// headers are sent to YouTube (fixes Error 152-4 on Android WebView).
/// Supports long-press for 2x speed boost on all platforms.
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
  WebViewController? _controller;
  String? _videoId;
  double _lastReportedProgress = -1.0;
  bool _isSpeedBoosted = false;
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    _videoId = _extractVideoId(widget.videoUrl);
    if (_videoId != null) {
      _initWebView();
    }
  }

  /// Extract YouTube video ID from various URL formats.
  static String? _extractVideoId(String url) {
    // youtube.com/watch?v=ID
    final watchMatch = RegExp(r'[?&]v=([a-zA-Z0-9_-]{11})').firstMatch(url);
    if (watchMatch != null) return watchMatch.group(1);

    // youtu.be/ID or youtube.com/embed/ID or youtube.com/shorts/ID
    final pathMatch =
        RegExp(r'(?:youtu\.be|youtube\.com/(?:embed|shorts))/([a-zA-Z0-9_-]{11})')
            .firstMatch(url);
    if (pathMatch != null) return pathMatch.group(1);

    // youtube.com/v/ID
    final vMatch =
        RegExp(r'youtube\.com/v/([a-zA-Z0-9_-]{11})').firstMatch(url);
    if (vMatch != null) return vMatch.group(1);

    // Bare ID (11 chars)
    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(url)) return url;

    return null;
  }

  void _initWebView() {
    late final PlatformWebViewControllerCreationParams params;

    if (!kIsWeb && Platform.isIOS) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black);

    // JavaScript channels for player ↔ Flutter communication
    controller.addJavaScriptChannel(
      'FlutterProgress',
      onMessageReceived: (message) {
        if (widget.onProgressChanged == null) return;
        final progress = double.tryParse(message.message) ?? 0.0;
        if ((progress - _lastReportedProgress).abs() >= 0.02) {
          _lastReportedProgress = progress;
          widget.onProgressChanged!(progress);
        }
      },
    );

    controller.addJavaScriptChannel(
      'FlutterPlayState',
      onMessageReceived: (message) {
        final isPlaying = message.message == '1';
        widget.onPlayStateChanged?.call(isPlaying);
      },
    );

    controller.addJavaScriptChannel(
      'FlutterReady',
      onMessageReceived: (_) {
        if (mounted) {
          setState(() => _isReady = true);
        }
      },
    );

    // Load the YouTube IFrame API HTML with proper baseUrl
    // Setting baseUrl to https://www.youtube.com ensures the WebView sends
    // a valid HTTP Referer header, which YouTube requires since July 2025.
    final html = _buildPlayerHtml(_videoId!);
    controller.loadHtmlString(
      html,
      baseUrl: 'https://www.youtube.com',
    );

    _controller = controller;
  }

  String _buildPlayerHtml(String videoId) {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body { width: 100%; height: 100%; overflow: hidden; background: #000; }
    #player { width: 100%; height: 100%; }
  </style>
</head>
<body>
  <div id="player"></div>
  <script>
    var tag = document.createElement('script');
    tag.src = 'https://www.youtube.com/iframe_api';
    var firstScriptTag = document.getElementsByTagName('script')[0];
    firstScriptTag.parentNode.insertBefore(tag, firstScriptTag);

    var player;
    var progressInterval;

    function onYouTubeIframeAPIReady() {
      player = new YT.Player('player', {
        videoId: '$videoId',
        playerVars: {
          'autoplay': 0,
          'controls': 1,
          'rel': 0,
          'modestbranding': 1,
          'playsinline': 1,
          'enablejsapi': 1,
          'origin': 'https://www.youtube.com',
          'fs': 1
        },
        events: {
          'onReady': onPlayerReady,
          'onStateChange': onPlayerStateChange
        }
      });
    }

    function onPlayerReady(event) {
      FlutterReady.postMessage('ready');
      startProgressTracking();
    }

    function onPlayerStateChange(event) {
      // YT.PlayerState.PLAYING = 1
      var isPlaying = (event.data === 1) ? '1' : '0';
      FlutterPlayState.postMessage(isPlaying);
    }

    function startProgressTracking() {
      progressInterval = setInterval(function() {
        if (player && player.getCurrentTime && player.getDuration) {
          var current = player.getCurrentTime();
          var duration = player.getDuration();
          if (duration > 0) {
            var progress = (current / duration);
            FlutterProgress.postMessage(progress.toString());
          }
        }
      }, 1000);
    }

    function setPlaybackRate(rate) {
      if (player && player.setPlaybackRate) {
        player.setPlaybackRate(rate);
      }
    }
  </script>
</body>
</html>
''';
  }

  // --- Long-press 2x speed (all platforms) ---
  void _startSpeedBoost() {
    setState(() => _isSpeedBoosted = true);
    _controller?.runJavaScript('setPlaybackRate(2.0)');
  }

  void _stopSpeedBoost() {
    setState(() => _isSpeedBoosted = false);
    _controller?.runJavaScript('setPlaybackRate(1.0)');
  }

  @override
  void dispose() {
    // No explicit close needed for WebViewController
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    if (_videoId == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(FacteurSpacing.space6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: colors.error,
              ),
              const SizedBox(height: FacteurSpacing.space4),
              Text(
                'Impossible de charger la vidéo YouTube',
                style:
                    textTheme.bodyLarge?.copyWith(color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final playerWidget = _controller != null
        ? WebViewWidget(controller: _controller!)
        : const SizedBox.shrink();

    // Wrap in AspectRatio for proper sizing
    final sizedPlayer = AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: playerWidget,
    );

    // Wrap player in GestureDetector for long-press 2x speed + Stack for overlay
    final playerWithSpeedBoost = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPressStart: (_) => _startSpeedBoost(),
      onLongPressEnd: (_) => _stopSpeedBoost(),
      child: Stack(
        children: [
          sizedPlayer,
          // 2x speed indicator overlay
          if (_isSpeedBoosted)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.fast_forward,
                      size: 14,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '2x',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
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

    // If no description or footer, return player directly so it respects
    // parent height constraints (important for 9:16 Shorts in bounded containers).
    if (widget.aspectRatio < 1.0 && widget.description == null && widget.footer == null) {
      return playerWithSpeedBoost;
    }

    // With description/footer, use scroll view for overflow content
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // YouTube Player with speed boost
          playerWithSpeedBoost,

          // Description
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
            const SizedBox(height: 32),
            widget.footer!,
            const SizedBox(height: 64),
          ],
        ],
      ),
    );
  }
}
