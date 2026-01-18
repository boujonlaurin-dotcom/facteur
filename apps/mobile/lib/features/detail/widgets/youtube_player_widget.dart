import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart' as mobile;
import 'package:youtube_player_iframe/youtube_player_iframe.dart' as web;

import '../../../../config/theme.dart';

/// YouTube video player widget (Story 5.2)
class YouTubePlayerWidget extends StatefulWidget {
  final String videoUrl;
  final String title;
  final String? description;

  const YouTubePlayerWidget({
    super.key,
    required this.videoUrl,
    required this.title,
    this.description,
    this.footer,
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

  @override
  void initState() {
    super.initState();
    // Common ID extraction
    // Using mobile package to extract ID works on both platforms typically as it's just regex
    _videoId = mobile.YoutubePlayer.convertUrlToId(widget.videoUrl);

    if (_videoId != null) {
      if (kIsWeb) {
        // Initialize Web Controller
        _webController = web.YoutubePlayerController.fromVideoId(
          videoId: _videoId!,
          autoPlay: false,
          params: const web.YoutubePlayerParams(
            showControls: true,
            showFullscreenButton: true,
          ),
        );
        _isPlayerReady = true; // Iframe handles loading state better internally
      } else {
        // Initialize Mobile Controller
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

        // Listener for Fullscreen rotation
        _mobileController.addListener(() {
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
        });
      }
    }
  }

  @override
  void dispose() {
    if (_videoId != null) {
      if (kIsWeb) {
        _webController.close();
      } else {
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
              // Player
              player,

              // Loading indicator
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

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // YouTube Player
          playerWidget,

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
            const SizedBox(height: 32),
          ],
        ],
      ),
    );
  }
}
