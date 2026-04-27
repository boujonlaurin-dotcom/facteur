import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../config/constants.dart';

/// Cross-platform network image.
///
/// On mobile (Android/iOS native) → `CachedNetworkImage` (disk cache).
/// On web → `Image.network` via le proxy backend `/api/images/proxy?url=...`.
/// Pourquoi le proxy : depuis Flutter 3.29 le rendu Web est forcé en CanvasKit,
/// qui dessine les images sur `<canvas>`. Toute image cross-origin sans en-tête
/// `Access-Control-Allow-Origin` produit un canvas taint → `errorBuilder`. Le
/// proxy re-sert l'image avec CORS + cache long. Le chemin mobile est
/// strictement inchangé pour éviter toute divergence app vs web.
class FacteurImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget Function(BuildContext context)? placeholder;
  final Widget Function(BuildContext context)? errorWidget;

  const FacteurImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  });

  /// Sur web, route l'URL via le proxy backend pour contourner le canvas
  /// taint CanvasKit. No-op si l'URL pointe déjà vers notre API.
  static String _resolveWebUrl(String url) {
    final base = ApiConstants.baseUrl;
    if (url.startsWith(base)) return url;
    return '${base}images/proxy?url=${Uri.encodeComponent(url)}';
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Image.network(
        _resolveWebUrl(imageUrl),
        width: width,
        height: height,
        fit: fit,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return placeholder?.call(context) ?? const SizedBox.shrink();
        },
        errorBuilder: (context, error, stackTrace) {
          return errorWidget?.call(context) ?? const SizedBox.shrink();
        },
      );
    }

    return CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      placeholder: placeholder != null
          ? (context, url) => placeholder!.call(context)
          : null,
      errorWidget: (context, url, error) =>
          errorWidget?.call(context) ?? const SizedBox.shrink(),
    );
  }
}
