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

  // Cache statique des URLs d'images échouées — persiste pendant la session.
  // Évite la correction de scroll causée par l'effondrement de hauteur
  // quand une carte avec image cassée repasse dans le viewport après avoir
  // été disposée (addAutomaticKeepAlives: false dans SliverList).
  static final Set<String> _failedUrls = {};

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
    if (url == null || url.isEmpty || _hasError || _failedUrls.contains(url)) {
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
            _failedUrls.add(url); // Cache immédiat pour éviter le re-collapse
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
