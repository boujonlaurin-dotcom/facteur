import 'package:flutter/material.dart';
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

  /// Session-wide cache of failed image URLs.
  /// Public so parents can check synchronously whether an image will render.
  static final Set<String> failedUrls = {};

  const FacteurThumbnail({
    super.key,
    required this.imageUrl,
    this.aspectRatio = 16 / 9,
    this.borderRadius,
    this.onError,
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

  @override
  Widget build(BuildContext context) {
    final url = widget.imageUrl;
    if (url == null || url.isEmpty || _hasError || FacteurThumbnail.failedUrls.contains(url)) {
      return const SizedBox.shrink();
    }

    final colors = context.facteurColors;

    return ClipRRect(
      borderRadius: widget.borderRadius ?? BorderRadius.zero,
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: FacteurImage(
          imageUrl: url,
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
            FacteurThumbnail.failedUrls.add(url);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() => _hasError = true);
                widget.onError?.call();
              }
            });
            return Container(color: colors.backgroundSecondary);
          },
        ),
      ),
    );
  }
}
