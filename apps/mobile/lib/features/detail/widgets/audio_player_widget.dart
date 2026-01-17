import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../../../config/theme.dart';

/// Audio player widget for podcast episodes (Story 5.2)
class AudioPlayerWidget extends StatefulWidget {
  final String audioUrl;
  final String title;
  final String? description;
  final String? thumbnailUrl;
  final int? durationSeconds;

  const AudioPlayerWidget({
    super.key,
    required this.audioUrl,
    required this.title,
    this.description,
    this.thumbnailUrl,
    this.durationSeconds,
  });

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  late AudioPlayer _player;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      await _player.setUrl(widget.audioUrl);
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Impossible de charger l\'audio';
      });
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '--:--';
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      final hours = duration.inHours.toString();
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    if (_error != null) {
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
                _error!,
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
      padding: const EdgeInsets.all(FacteurSpacing.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail
          if (widget.thumbnailUrl != null)
            Container(
              width: double.infinity,
              height: 200,
              margin: const EdgeInsets.only(bottom: FacteurSpacing.space4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(FacteurRadius.large),
                image: DecorationImage(
                  image: NetworkImage(widget.thumbnailUrl!),
                  fit: BoxFit.cover,
                ),
              ),
            ),

          // Player controls
          Container(
            padding: const EdgeInsets.all(FacteurSpacing.space4),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(FacteurRadius.large),
              border: Border.all(color: colors.surfaceElevated),
            ),
            child: Column(
              children: [
                // Progress bar
                StreamBuilder<Duration?>(
                  stream: _player.positionStream,
                  builder: (context, snapshot) {
                    final position = snapshot.data ?? Duration.zero;
                    final duration = _player.duration ?? Duration.zero;

                    return Column(
                      children: [
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: colors.primary,
                            inactiveTrackColor: colors.surfaceElevated,
                            thumbColor: colors.primary,
                            trackHeight: 4,
                          ),
                          child: Slider(
                            value: position.inMilliseconds.toDouble(),
                            max: duration.inMilliseconds
                                .toDouble()
                                .clamp(1, double.infinity),
                            onChanged: (value) {
                              _player
                                  .seek(Duration(milliseconds: value.toInt()));
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatDuration(position),
                                style: textTheme.bodySmall?.copyWith(
                                  color: colors.textTertiary,
                                ),
                              ),
                              Text(
                                _formatDuration(duration),
                                style: textTheme.bodySmall?.copyWith(
                                  color: colors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),

                const SizedBox(height: FacteurSpacing.space4),

                // Play controls
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Rewind 15s
                    IconButton(
                      icon: Icon(
                        Icons.replay_10,
                        color: colors.textSecondary,
                        size: 32,
                      ),
                      onPressed: () {
                        final newPosition =
                            _player.position - const Duration(seconds: 10);
                        _player.seek(newPosition < Duration.zero
                            ? Duration.zero
                            : newPosition);
                      },
                    ),

                    const SizedBox(width: FacteurSpacing.space4),

                    // Play/Pause button
                    StreamBuilder<PlayerState>(
                      stream: _player.playerStateStream,
                      builder: (context, snapshot) {
                        final playerState = snapshot.data;
                        final processingState = playerState?.processingState;
                        final playing = playerState?.playing ?? false;

                        if (_isLoading ||
                            processingState == ProcessingState.loading) {
                          return Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: colors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          );
                        }

                        return GestureDetector(
                          onTap: () {
                            if (playing) {
                              _player.pause();
                            } else {
                              _player.play();
                            }
                          },
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: colors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              playing ? Icons.pause : Icons.play_arrow,
                              color: Colors.white,
                              size: 32,
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(width: FacteurSpacing.space4),

                    // Forward 30s
                    IconButton(
                      icon: Icon(
                        Icons.forward_30,
                        color: colors.textSecondary,
                        size: 32,
                      ),
                      onPressed: () {
                        final duration = _player.duration ?? Duration.zero;
                        final newPosition =
                            _player.position + const Duration(seconds: 30);
                        _player.seek(
                            newPosition > duration ? duration : newPosition);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: FacteurSpacing.space6),

          // Description
          if (widget.description != null && widget.description!.isNotEmpty)
            Text(
              widget.description!,
              style: textTheme.bodyLarge?.copyWith(
                color: colors.textSecondary,
                height: 1.6,
              ),
            ),
        ],
      ),
    );
  }
}
