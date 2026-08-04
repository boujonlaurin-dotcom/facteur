import 'package:flutter/material.dart';
import '../../config/theme.dart';
import 'facteur_image.dart';

/// Article thumbnail that collapses entirely on load error.
/// Wraps [FacteurImage] in ClipRRect + AspectRatio with collapse-on-error.
class FacteurThumbnail extends StatefulWidget {
  final String? imageUrl;
  final double aspectRatio;
  final BorderRadius? borderRadius;
  final Widget? overlay;
  final String? durationLabel;
  final VoidCallback? onError;
  final bool isVideo;

  /// Largeur (px physiques) de décodage en cache mémoire. Null = largeur
  /// d'écran × devicePixelRatio (le thumbnail est quasi toujours pleine
  /// largeur) ; à surcharger pour les rendus plus étroits.
  final int? memCacheWidth;

  /// Public accessor for failed image URLs cached during this session.
  static Set<String> get failedUrls => _FacteurThumbnailState._failedUrls;

  /// Déclare une URL comme morte pour la session, depuis un rendu d'image qui
  /// n'est pas un [FacteurThumbnail] (la carte de tri, par exemple, réserve un
  /// slot de hauteur fixe et ne peut donc pas se replier comme lui). Passe par
  /// une méthode plutôt que par la mutation directe du `Set` exposé, pour que
  /// le cache garde un propriétaire et une politique d'éviction unique.
  static void markFailed(String url) =>
      _FacteurThumbnailState._failedUrls.add(url);

  const FacteurThumbnail({
    super.key,
    required this.imageUrl,
    this.aspectRatio = 16 / 9,
    this.borderRadius,
    this.overlay,
    this.durationLabel,
    this.onError,
    this.isVideo = false,
    this.memCacheWidth,
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
        child: Stack(
          fit: StackFit.expand,
          children: [
            FacteurImage(
              imageUrl: url,
              fit: BoxFit.cover,
              memCacheWidth: widget.memCacheWidth ??
                  (MediaQuery.sizeOf(context).width *
                          MediaQuery.devicePixelRatioOf(context))
                      .round(),
              placeholder: (context) => Container(
                color: colors.backgroundSecondary,
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.primary.withOpacity(0.5),
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
            // Dark scrim + centered overlay
            if (widget.overlay != null) ...[
              Container(color: Colors.black.withOpacity(0.3)),
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
                    color: Colors.black.withOpacity(0.75),
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
}
