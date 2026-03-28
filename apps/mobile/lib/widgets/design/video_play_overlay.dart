import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Play button overlay for video thumbnails.
/// Renders a semi-transparent white circle with a play icon.
/// The scrim is handled by [FacteurThumbnail], not here.
class VideoPlayOverlay extends StatelessWidget {
  const VideoPlayOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Icon(
          PhosphorIcons.play(PhosphorIconsStyle.fill),
          size: 24,
          color: Colors.black87,
        ),
      ),
    );
  }
}
