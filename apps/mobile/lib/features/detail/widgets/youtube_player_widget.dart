import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart' as mobile;
import 'package:youtube_player_iframe/youtube_player_iframe.dart' as web;

import '../../../../config/theme.dart';

/// YouTube video player widget (Story 5.2)
/// Supports long-press for 2x speed boost.
class YouTubePlayerWidget extends StatefulWidget {
  final String videoUrl;
  final String title;
  final String? description;
  final ValueChanged<double>? onProgressChanged; // 0.0 to 1.0

  const YouTubePlayerWidget({
    super.key,
    required this.videoUrl,
    required this.title,
    this.description,
    this.footer,
    this.onProgressChanged,
  });

  final Widget? footer;

  @override
  State<YouTubePlayerWidget> createState() => _YouTubePlayerWidgetState();
}

class _YouTubePlayerWidgetState extends State<YouTubePlayerWidget> {
  // Mobile Controller
  late mobile.YoutubePlayerController _mobileController;

  // Web Controller
  late web.YoutubePlayerController _webController;

  String? _videoId;
  bool _isPlayerReady = false;
  double _lastReportedProgress = -1.0;
  Timer? _webProgressTimer;

  // Long-press 2x speed state
  bool _isSpeedBoosted = false;

  @override
  void initState() {
    super.initState();
    _videoId = mobile.YoutubePlayer.convertUrlToId(widget.videoUrl);
    // Fallback for /shorts/ URLs not supported by convertUrlToId
    _videoId ??= _extractShortsId(widget.videoUrl);

    if (_videoId != null) {
      if (kIsWeb) {
        _webController = web.YoutubePlayerController.fromVideoId(
          videoId: _videoId!,
          autoPlay: false,
          params: const web.YoutubePlayerParams(
            showControls: true,
            showFullscreenButton: true,
          ),
        );
        _isPlayerReady = true;
        _startWebProgressTracking();
      } else {
        _mobileController = mobile.YoutubePlayerController(
          initialVideoId: _videoId!,
          flags: const mobile.YoutubePlayerFlags(
            autoPlay: false,
            mute: false,
            enableCaption: true,
            hideControls: false,
            hideThumbnail: false,
            controlsVisibleAtStart: true,
          ),
        );
        _mobileController.addListener(_onMobileControllerUpdate);
      }
    }
  }

  void _onMobileControllerUpdate() {
    if (_mobileController.value.isFullScreen) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }

    if (widget.onProgressChanged == null) return;
    final position = _mobileController.value.position;
    final duration = _mobileController.metadata.duration;
    if (duration.inMilliseconds > 0) {
      final progress =
          (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
      if ((progress - _lastReportedProgress).abs() >= 0.02) {
        _lastReportedProgress = progress;
        widget.onProgressChanged!(progress);
      }
    }
  }

  void _startWebProgressTracking() {
    _webProgressTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) async {
        if (widget.onProgressChanged == null) return;
        try {
          final currentTime = await _webController.currentTime;
          final duration = await _webController.duration;
          if (duration > 0) {
            final progress = (currentTime / duration).clamp(0.0, 1.0);
            if ((progress - _lastReportedProgress).abs() >= 0.02) {
              _lastReportedProgress = progress;
              widget.onProgressChanged!(progress);
            }
          }
        } catch (_) {
          // Controller may not be ready yet
        }
      },
    );
  }

  /// Extract video ID from /shorts/ URLs not handled by youtube_player_flutter.
  static String? _extractShortsId(String url) {
    final match = RegExp(r'youtube\.com/shorts/([\w-]+)').firstMatch(url);
    return match?.group(1);
  }

  // --- Long-press 2x speed ---
  void _startSpeedBoost() {
    setState(() => _isSpeedBoosted = true);
    if (kIsWeb) {
      _webController.setPlaybackRate(2.0);
    }
    // Mobile: youtube_player_flutter v9 doesn't expose setPlaybackRate()
  }

  void _stopSpeedBoost() {
    setState(() => _isSpeedBoosted = false);
    if (kIsWeb) {
      _webController.setPlaybackRate(1.0);
    }
  }

  @override
  void dispose() {
    _webProgressTimer?.cancel();
    if (_videoId != null) {
      if (kIsWeb) {
        _webController.close();
      } else {
        _mobileController.removeListener(_onMobileControllerUpdate);
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
        _mobileController.dispose();
      }
    }
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

    Widget playerWidget;

    if (kIsWeb) {
      playerWidget = web.YoutubePlayer(
        controller: _webController,
        aspectRatio: 16 / 9,
      );
    } else {
      playerWidget = mobile.YoutubePlayerBuilder(
        player: mobile.YoutubePlayer(
          controller: _mobileController,
          showVideoProgressIndicator: true,
          progressIndicatorColor: colors.primary,
          progressColors: mobile.ProgressBarColors(
            playedColor: colors.primary,
            handleColor: colors.primary,
            bufferedColor: colors.surfaceElevated,
            backgroundColor: colors.surface,
          ),
          onReady: () {
            setState(() => _isPlayerReady = true);
          },
        ),
        builder: (context, player) {
          return Column(
            children: [
              player,
              if (!_isPlayerReady)
                Container(
                  height: 200,
                  color: colors.surface,
                  child: Center(
                    child: CircularProgressIndicator(
                      color: colors.primary,
                    ),
                  ),
                ),
            ],
          );
        },
      );
    }

    // Wrap player in GestureDetector for long-press 2x speed + Stack for overlay
    final playerWithSpeedBoost = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPressStart: (_) => _startSpeedBoost(),
      onLongPressEnd: (_) => _stopSpeedBoost(),
      child: Stack(
        children: [
          playerWidget,
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
            const SizedBox(height: 32),
            widget.footer!,
            const SizedBox(height: 64),
          ],
        ],
      ),
    );
  }
}
