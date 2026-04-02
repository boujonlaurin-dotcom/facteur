import 'dart:async';

import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../../../config/theme.dart';

/// YouTube video player widget (Story 5.2)
/// Unified on youtube_player_iframe for all platforms.
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
  late YoutubePlayerController _controller;
  String? _videoId;
  double _lastReportedProgress = -1.0;
  Timer? _progressTimer;
  StreamSubscription<YoutubePlayerValue>? _playStateSubscription;

  // Long-press 2x speed state
  bool _isSpeedBoosted = false;

  @override
  void initState() {
    super.initState();
    _videoId = YoutubePlayerController.convertUrlToId(widget.videoUrl);

    if (_videoId != null) {
      _controller = YoutubePlayerController.fromVideoId(
        videoId: _videoId!,
        autoPlay: false,
        params: const YoutubePlayerParams(
          showControls: true,
          showFullscreenButton: true,
          desktopMode: true,
        ),
      );
      _startProgressTracking();
      _startPlayStateTracking();
    }
  }

  void _startProgressTracking() {
    _progressTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) async {
        if (widget.onProgressChanged == null) return;
        try {
          final currentTime = await _controller.currentTime;
          final duration = await _controller.duration;
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

  void _startPlayStateTracking() {
    _playStateSubscription = _controller.listen((value) {
      widget.onPlayStateChanged
          ?.call(value.playerState == PlayerState.playing);
    });
  }

  // --- Long-press 2x speed (all platforms) ---
  void _startSpeedBoost() {
    setState(() => _isSpeedBoosted = true);
    _controller.setPlaybackRate(2.0);
  }

  void _stopSpeedBoost() {
    setState(() => _isSpeedBoosted = false);
    _controller.setPlaybackRate(1.0);
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _playStateSubscription?.cancel();
    if (_videoId != null) {
      _controller.close();
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

    final playerWidget = YoutubePlayer(
      controller: _controller,
      aspectRatio: widget.aspectRatio,
    );

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
