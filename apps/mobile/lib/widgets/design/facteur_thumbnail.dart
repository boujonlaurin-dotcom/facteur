import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../config/theme.dart';
import 'facteur_image.dart';

/// Article thumbnail that collapses entirely on load error.
/// Wraps [FacteurImage] in ClipRRect + AspectRatio with collapse-on-error.
class FacteurThumbnail extends StatefulWidget {
  final String? imageUrl;
  final double aspectRatio;
  final BorderRadius? borderRadius;
  /// Called once when the image fails to load.
  final VoidCallback? onError;
  final Widget? overlay;
  final String? durationLabel;
  final bool isVideo;

  /// Session-wide cache of failed image URLs.
  /// Public so parents can check synchronously whether an image will render.
  static final Set<String> failedUrls = {};

  const FacteurThumbnail({
    super.key,
    required this.imageUrl,
    this.aspectRatio = 16 / 9,
    this.borderRadius,
    this.onError,
    this.overlay,
    this.durationLabel,
    this.isVideo = false,
  });

  @override
  State<FacteurThumbnail> createState() => _FacteurThumbnailState();
}

class _FacteurThumbnailState extends State<FacteurThumbnail> {
  bool _hasError = false;

  @override
  void didUpdateWidget(FacteurThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _hasError = false;
    }
  }

  bool get _hasValidImage {
    final url = widget.imageUrl;
    return url != null &&
        url.isNotEmpty &&
        !_hasError &&
        !FacteurThumbnail.failedUrls.contains(url);
  }

  @override
  Widget build(BuildContext context) {
    // No image and not a video → collapse
    if (!_hasValidImage && !widget.isVideo) {
      return const SizedBox.shrink();
    }

    final colors = context.facteurColors;

    return ClipRRect(
      borderRadius: widget.borderRadius ?? BorderRadius.zero,
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_hasValidImage)
              FacteurImage(
                imageUrl: widget.imageUrl!,
                fit: BoxFit.cover,
                placeholder: (context) => Container(
                  color: colors.backgroundSecondary,
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.primary.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                errorWidget: (context) {
                  FacteurThumbnail.failedUrls.add(widget.imageUrl!);
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() => _hasError = true);
                      widget.onError?.call();
                    }
                  });
                  return Container(color: colors.backgroundSecondary);
                },
              )
            else if (widget.isVideo)
              _buildVideoPlaceholder(),
            // Dark scrim + centered overlay (only on real images, not video placeholder)
            if (widget.overlay != null && _hasValidImage) ...[
              Container(color: Colors.black.withValues(alpha: 0.3)),
              Center(child: widget.overlay!),
            ],
            // Duration pill (bottom-right)
            if (widget.durationLabel != null)
              Positioned(
                bottom: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    widget.durationLabel!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPlaceholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1A1A2E),
            Color(0xFF16213E),
            Color(0xFF0F3460),
          ],
        ),
      ),
      child: Center(
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFFFF0000).withValues(alpha: 0.9),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF0000).withValues(alpha: 0.3),
                blurRadius: 16,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(left: 3),
              child: Icon(
                PhosphorIcons.play(PhosphorIconsStyle.fill),
                size: 24,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
