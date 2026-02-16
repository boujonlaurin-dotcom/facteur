import 'package:flutter/material.dart';
import '../../config/theme.dart';
import 'facteur_image.dart';

/// Article thumbnail that collapses entirely on load error.
/// Wraps [FacteurImage] in ClipRRect + AspectRatio with collapse-on-error.
class FacteurThumbnail extends StatefulWidget {
  final String? imageUrl;
  final double aspectRatio;
  final BorderRadius? borderRadius;

  const FacteurThumbnail({
    super.key,
    required this.imageUrl,
    this.aspectRatio = 16 / 9,
    this.borderRadius,
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
    if (widget.imageUrl == null || widget.imageUrl!.isEmpty || _hasError) {
      return const SizedBox.shrink();
    }

    final colors = context.facteurColors;

    return ClipRRect(
      borderRadius: widget.borderRadius ?? BorderRadius.zero,
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: FacteurImage(
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
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _hasError = true);
            });
            return Container(color: colors.backgroundSecondary);
          },
        ),
      ),
    );
  }
}
