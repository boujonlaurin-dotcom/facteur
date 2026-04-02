import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../../../config/theme.dart';

/// Extracts YouTube video ID from various URL formats.
String? _extractVideoId(String url) {
  final patterns = [
    RegExp(r'(?:youtube\.com/watch\?.*v=|youtu\.be/|youtube\.com/embed/|youtube\.com/shorts/)([a-zA-Z0-9_-]{11})'),
  ];
  for (final pattern in patterns) {
    final match = pattern.firstMatch(url);
    if (match != null) return match.group(1);
  }
  // Fallback: if URL is just the video ID itself
  if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(url)) return url;
  return null;
}

/// YouTube video player widget (Story 5.2)
///
/// Uses youtube_player_iframe for all platforms (WebView-based).
/// The old youtube_player_flutter package used the deprecated Android
/// YouTube Player API which caused Error 152-4 on Android devices.
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
  late YoutubePlayerController _controller;

  String? _videoId;
  double _lastReportedProgress = -1.0;
  Timer? _progressTimer;

  @override
  void initState() {
    super.initState();
    _videoId = _extractVideoId(widget.videoUrl);

    if (_videoId != null) {
      _controller = YoutubePlayerController.fromVideoId(
        videoId: _videoId!,
        autoPlay: false,
        params: const YoutubePlayerParams(
          showControls: true,
          showFullscreenButton: true,
        ),
      );
      _startProgressTracking();
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

  @override
  void dispose() {
    _progressTimer?.cancel();
    if (_videoId != null) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
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

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // YouTube Player
          YoutubePlayer(
            controller: _controller,
            aspectRatio: 16 / 9,
          ),

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
